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
  sellAmount: string; // Amount to sell in wei
  enabled?: boolean;
}

// Use our aggregator instead of Bebop
const AGGREGATOR_URL = process.env.NEXT_PUBLIC_AGGREGATOR_URL || "http://localhost:3002";

export function useBebopQuote({ buyToken, sellToken, sellAmount, enabled = true }: UseBebopQuoteParams) {
  const { address: takerAddress } = useAccount();
  const chainId = useChainId();

  return useQuery<BebopQuote | null>({
    queryKey: ["bebopQuote", buyToken, sellToken, sellAmount, takerAddress, chainId],
    queryFn: async () => {
      if (!takerAddress || !buyToken || !sellToken || !sellAmount) {
        return null;
      }

      const params = new URLSearchParams({
        buy_tokens: buyToken,
        sell_tokens: sellToken,
        sell_amounts: sellAmount,
        taker_address: takerAddress,
      });

      console.log("📞 Requesting quote from aggregator");
      console.log("   Params:", params.toString());

      const url = `${AGGREGATOR_URL}/quote?${params.toString()}`;
      console.log("   URL:", url);

      const response = await fetch(url);

      if (!response.ok) {
        const errorText = await response.text();
        console.error("❌ Aggregator API error:", response.status, errorText);
        throw new Error(`Aggregator API error: ${response.statusText}`);
      }

      const data = await response.json();
      console.log("✅ Aggregator response:", data);
      return data;
    },
    enabled: enabled && !!takerAddress && !!buyToken && !!sellToken && !!sellAmount,
    staleTime: 15_000, // 15 seconds
    refetchInterval: 15_000, // Refresh every 15 seconds
    retry: 2,
  });
}
