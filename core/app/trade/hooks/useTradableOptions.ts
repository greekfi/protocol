import { useMemo } from "react";
import { useBrowseChainId } from "../../hooks/useBrowseChain";
import { useChainEvents, type OptionCreatedEvent } from "../../hooks/useChainEvents";

export interface TradableOption {
  optionAddress: string;
  collateralAddress: string;
  considerationAddress: string;
  expiration: bigint;
  strike: bigint;
  isPut: boolean;
  redemptionAddress: string;
}

/**
 * Returns all not-yet-expired options where `underlyingToken` matches either
 * the collateral side (calls) or the consideration side (puts).
 *
 * Sourced via {@link useChainEvents}, which now hits the market-maker's
 * /events endpoint (api.greek.finance) — same backend that prices /options,
 * single round-trip per page load. Returns [] cleanly while a chain's first
 * cold-sync is still running.
 */
export function useTradableOptions(underlyingToken: string | null) {
  const chainId = useBrowseChainId();
  const { data: events = [], isLoading, error } = useChainEvents(chainId);

  const data = useMemo<TradableOption[]>(() => {
    if (!underlyingToken) return [];
    const token = underlyingToken.toLowerCase();
    const now = BigInt(Math.floor(Date.now() / 1000));

    const matches = events.filter((e: OptionCreatedEvent) => {
      const c = e.args.collateral.toLowerCase();
      const s = e.args.consideration.toLowerCase();
      return c === token || s === token;
    });

    return matches
      .map<TradableOption>(e => ({
        optionAddress: e.args.option,
        collateralAddress: e.args.collateral,
        considerationAddress: e.args.consideration,
        expiration: BigInt(e.args.expirationDate),
        strike: BigInt(e.args.strike),
        isPut: e.args.isPut,
        redemptionAddress: e.args.receipt,
      }))
      .filter(opt => opt.expiration > now);
  }, [events, underlyingToken]);

  return {
    data,
    isLoading,
    error,
  };
}
