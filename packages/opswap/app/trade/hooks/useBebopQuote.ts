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

const CHAIN_NAMES: Record<number, string> = {
  1: "ethereum",
  1301: "unichain", // You may need to verify Bebop's chain name for Unichain
  11155111: "sepolia",
};

export function useBebopQuote({ buyToken, sellToken, sellAmount, enabled = true }: UseBebopQuoteParams) {
  const { address: takerAddress } = useAccount();
  const chainId = useChainId();

  return useQuery<BebopQuote | null>({
    queryKey: ["bebopQuote", buyToken, sellToken, sellAmount, takerAddress, chainId],
    queryFn: async () => {
      if (!takerAddress || !buyToken || !sellToken || !sellAmount) {
        return null;
      }

      const chainName = CHAIN_NAMES[chainId] || "ethereum";

      const params = new URLSearchParams({
        buy_tokens: buyToken,
        sell_tokens: sellToken,
        sell_amounts: sellAmount,
        taker_address: takerAddress,
        gasless: "false",
        include_routes: "JAMv2",
        receiver_address: "",
        source: "bebop.xyz",
        approval_type: "Standard",
        skip_taker_checks: "true",
      });

      const url = `https://api.bebop.xyz/router/${chainName}/v1/quote?${params.toString()}`;

      const response = await fetch(url);

      if (!response.ok) {
        throw new Error(`Bebop API error: ${response.statusText}`);
      }

      const data = await response.json();
      return data;
    },
    enabled: enabled && !!takerAddress && !!buyToken && !!sellToken && !!sellAmount,
    staleTime: 15_000, // 15 seconds
    refetchInterval: 15_000, // Refresh every 15 seconds
    retry: 2,
  });
}
