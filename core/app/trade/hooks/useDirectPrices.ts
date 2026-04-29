import { useQuery } from "@tanstack/react-query";
import { useChainId } from "wagmi";

const DIRECT_API_URL = process.env.NEXT_PUBLIC_DIRECT_API_URL || "https://api.greek.finance";

export interface DirectOption {
  address: string;
  bid: number | null;
  ask: number | null;
  mid: number | null;
  iv: number | null;
  spotPrice: number | null;
}

export interface DirectPrice {
  bid?: number;
  ask?: number;
  mid?: number;
  iv?: number;
  spotPrice?: number;
}

/**
 * Polls the direct quote server's /options endpoint and returns a map of
 * option address → {bid, ask, mid, iv}. Intended as a drop-in replacement
 * for the WebSocket pricing stream when the relay is unavailable.
 */
export function useDirectPrices() {
  const chainId = useChainId();
  return useQuery<Map<string, DirectPrice>>({
    queryKey: ["directPrices", DIRECT_API_URL, chainId],
    queryFn: async () => {
      const res = await fetch(`${DIRECT_API_URL}/options?chainId=${chainId}`);
      if (!res.ok) throw new Error(`Direct /options failed: ${res.status}`);
      const body = (await res.json()) as { options: DirectOption[] };
      const map = new Map<string, DirectPrice>();
      for (const o of body.options ?? []) {
        map.set(o.address.toLowerCase(), {
          bid: o.bid ?? undefined,
          ask: o.ask ?? undefined,
          mid: o.mid ?? undefined,
          iv: o.iv ?? undefined,
          spotPrice: o.spotPrice ?? undefined,
        });
      }
      return map;
    },
    staleTime: 10_000,
    refetchInterval: 10_000,
    retry: 1,
  });
}
