import { useQuery } from "@tanstack/react-query";
import { useAccount, useChainId } from "wagmi";

export interface RfqQuote {
  quoteId: string;
  buyToken: string;
  sellToken: string;
  buyAmount: string;
  sellAmount: string;
  price: string;
  expiry: number;
  makerAddress: string;
  greeks?: {
    delta: number;
    gamma: number;
    theta: number;
    vega: number;
  };
  spotPrice?: number;
  iv?: number;
  routes?: string[];
  estimatedGas?: string;
}

interface UseRfqQuoteParams {
  buyToken: string;
  sellToken: string;
  sellAmount?: string;
  buyAmount?: string;
  enabled?: boolean;
}

// RFQ-Direct API endpoints by chain ID
const RFQ_API_URLS: Record<number, string> = {
  1: process.env.NEXT_PUBLIC_RFQ_API_URL || "http://localhost:3010",
  1301: process.env.NEXT_PUBLIC_RFQ_API_URL || "http://localhost:3010",
  11155111: process.env.NEXT_PUBLIC_RFQ_API_URL || "http://localhost:3010",
  31337: process.env.NEXT_PUBLIC_RFQ_API_URL || "http://localhost:3010",
};

export function useRfqQuote({ buyToken, sellToken, sellAmount, buyAmount, enabled = true }: UseRfqQuoteParams) {
  const { address: takerAddress } = useAccount();
  const chainId = useChainId();

  return useQuery<RfqQuote | null>({
    queryKey: ["rfqQuote", buyToken, sellToken, sellAmount, buyAmount, takerAddress, chainId],
    queryFn: async () => {
      if (!takerAddress || !buyToken || !sellToken || (!sellAmount && !buyAmount)) {
        return null;
      }

      const rfqApiUrl = RFQ_API_URLS[chainId] || RFQ_API_URLS[1];

      const params: Record<string, string> = {
        buyToken,
        sellToken,
        takerAddress,
      };

      if (sellAmount) {
        params.sellAmount = sellAmount;
      } else if (buyAmount) {
        params.buyAmount = buyAmount;
      }

      const searchParams = new URLSearchParams(params);
      const url = `${rfqApiUrl}/quote?${searchParams.toString()}`;

      console.log("📞 Requesting quote from RFQ-Direct");
      console.log("   URL:", url);

      const response = await fetch(url);

      if (!response.ok) {
        const errorText = await response.text();
        console.error("❌ RFQ-Direct API error:", response.status, errorText);
        try {
          const errorJson = JSON.parse(errorText);
          throw new Error(errorJson.error || `RFQ API error: ${response.statusText}`);
        } catch {
          throw new Error(`RFQ API error: ${response.statusText}`);
        }
      }

      const data = await response.json();
      console.log("✅ RFQ-Direct response:", data);
      return data;
    },
    enabled: enabled && !!takerAddress && !!buyToken && !!sellToken && (!!sellAmount || !!buyAmount),
    staleTime: 15_000,
    refetchInterval: 15_000,
    retry: 2,
  });
}

// Hook to get all available options from RFQ-Direct
export function useRfqOptions() {
  const chainId = useChainId();

  return useQuery({
    queryKey: ["rfqOptions", chainId],
    queryFn: async () => {
      const rfqApiUrl = RFQ_API_URLS[chainId] || RFQ_API_URLS[1];
      const url = `${rfqApiUrl}/options`;

      const response = await fetch(url);
      if (!response.ok) {
        throw new Error(`Failed to fetch options: ${response.statusText}`);
      }

      const data = await response.json();
      return data.options || [];
    },
    staleTime: 30_000,
    refetchInterval: 30_000,
  });
}

// Hook to get health status of RFQ-Direct service
export function useRfqHealth() {
  const chainId = useChainId();

  return useQuery({
    queryKey: ["rfqHealth", chainId],
    queryFn: async () => {
      const rfqApiUrl = RFQ_API_URLS[chainId] || RFQ_API_URLS[1];
      const url = `${rfqApiUrl}/health`;

      const response = await fetch(url);
      if (!response.ok) {
        throw new Error(`Health check failed: ${response.statusText}`);
      }

      return response.json();
    },
    staleTime: 10_000,
    refetchInterval: 10_000,
    retry: 1,
  });
}
