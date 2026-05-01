import { useQuery } from "@tanstack/react-query";

/**
 * Frontend client for greek-events (https://greek-events.fly.dev), which
 * indexes Factory.OptionCreated across configured chains and serves them
 * over HTTP. Replaces per-page-load `getLogs` scans against public RPCs.
 *
 * Set `NEXT_PUBLIC_EVENTS_API_URL` to override (default: greek-events.fly.dev).
 *
 * Schema mirrors the one defined in greekfi/event-sync's `src/storage.ts`:
 * StoredEvent with bigint fields encoded as decimal strings, dates as numbers.
 */

const EVENTS_API_URL =
  process.env.NEXT_PUBLIC_EVENTS_API_URL || "https://greek-events.fly.dev";

export interface OptionCreatedEvent {
  blockNumber: string;
  txHash: string;
  logIndex: number;
  args: {
    collateral: string;
    consideration: string;
    expirationDate: number;
    /** 18-decimal fixed-point bigint, as a decimal string. */
    strike: string;
    isPut: boolean;
    isEuro: boolean;
    /** Length in seconds of the post-expiry exercise window. */
    windowSeconds: number;
    /** The Option (long-side) ERC20 address. */
    option: string;
    /** The paired Receipt (short-side) ERC20 address. */
    receipt: string;
  };
}

/**
 * Fetch every OptionCreated event for a chain from greek-events. Returns []
 * if the chain isn't indexed yet (e.g. mainnet — no Greek deployment), or
 * while a chain's first cold-sync is still running.
 */
export function useChainEvents(chainId: number | undefined) {
  return useQuery<OptionCreatedEvent[]>({
    queryKey: ["chainEvents", EVENTS_API_URL, chainId],
    queryFn: async () => {
      if (!chainId) return [];
      const url = `${EVENTS_API_URL}/events?chainId=${chainId}`;
      const res = await fetch(url);
      if (!res.ok) throw new Error(`events api ${res.status}: ${res.statusText}`);
      const body = (await res.json()) as { count: number; events: OptionCreatedEvent[] };
      return body.events ?? [];
    },
    enabled: Boolean(chainId),
    staleTime: 30_000,
    refetchInterval: 30_000,
  });
}
