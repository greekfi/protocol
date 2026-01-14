import { useQuery } from "@tanstack/react-query";
import { useAccount, useChainId } from "wagmi";

export interface BebopQuote {
  buyAmount: string;
  sellAmount: string;
  price: string;
  estimatedGas: string;
  tx: {
    to: string;
    data: string;
    value: string;
    gas: string;
    gasPrice: string;
  };
  approvalTarget?: string;
  routes?: any[];
}

interface UseBebopQuoteParams {
  buyToken: string; // Token address to buy
  sellToken: string; // Token address to sell
  sellAmount?: string; // Amount to sell in wei (optional)
  buyAmount?: string; // Amount to buy in wei (optional)
  enabled?: boolean;
}

// Bebop API endpoints by chain ID
const BEBOP_API_URLS: Record<number, string> = {
  1: "https://api.bebop.xyz/pmm/ethereum/v3", // Ethereum Mainnet
  1301: "https://api.bebop.xyz/pmm/unichain/v3", // Unichain Sepolia
  11155111: "https://api.bebop.xyz/pmm/sepolia/v3", // Sepolia
};

export function useBebopQuote({ buyToken, sellToken, sellAmount, buyAmount, enabled = true }: UseBebopQuoteParams) {
  const { address: takerAddress } = useAccount();
  const chainId = useChainId();

  return useQuery<BebopQuote | null>({
    queryKey: ["bebopQuote", buyToken, sellToken, sellAmount, buyAmount, takerAddress, chainId],
    queryFn: async () => {
      if (!takerAddress || !buyToken || !sellToken || (!sellAmount && !buyAmount)) {
        return null;
      }

      const bebopApiUrl = BEBOP_API_URLS[chainId];
      if (!bebopApiUrl) {
        throw new Error(`Bebop API not available for chain ${chainId}`);
      }

      const params: Record<string, string> = {
        buy_tokens: buyToken,
        sell_tokens: sellToken,
        taker_address: takerAddress,
      };

      // Use either sell_amounts or buy_amounts depending on what's provided
      if (sellAmount) {
        params.sell_amounts = sellAmount;
      } else if (buyAmount) {
        params.buy_amounts = buyAmount;
      }

      const searchParams = new URLSearchParams(params);

      console.log("📞 Requesting quote from Bebop");
      console.log("   Params:", searchParams.toString());

      const url = `${bebopApiUrl}/quote?${searchParams.toString()}`;
      console.log("   URL:", url);

      const response = await fetch(url);

      if (!response.ok) {
        const errorText = await response.text();
        console.error("❌ Bebop API error:", response.status, errorText);
        throw new Error(`Bebop API error: ${response.statusText}`);
      }

      const data = await response.json();
      console.log("✅ Bebop response:", data);
      return data;
    },
    enabled: enabled && !!takerAddress && !!buyToken && !!sellToken && (!!sellAmount || !!buyAmount),
    staleTime: 15_000, // 15 seconds
    refetchInterval: 15_000, // Refresh every 15 seconds
    retry: 2,
  });
}
