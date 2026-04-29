import { formatUnits } from "viem";
import type { TradableOption } from "../trade/hooks/useTradableOptions";

/**
 * Strike-price formatting shared across /trade, /yield, and any other grid.
 *
 * Strike storage is 18-decimal fixed-point. For puts the contract stores the
 * *inverse* (1e36 / humanStrike) so that call and put strikes share the same
 * encoding on chain. {@link displayStrike} flips that back so callers always
 * see the human-readable strike.
 *
 * {@link formatStrikeValue} renders with thousands-separators and a
 * scale-aware number of decimals: at $100+ strikes a $0.01 difference is
 * noise, but for sub-dollar low-cap tokens the digits matter — so we keep
 * three significant figures there.
 */

/** Returns the human-readable strike (un-inverted for puts). */
export function displayStrike(opt: { strike: bigint; isPut: boolean }): bigint {
  if (opt.isPut && opt.strike > 0n) return 10n ** 36n / opt.strike;
  return opt.strike;
}

/**
 * Format a 18-decimal-fixed-point strike for display.
 * - `>= 100`     → 0 decimals, commas (e.g. "3,000")
 * - `>= 1`       → up to 2 decimals (e.g. "12.34")
 * - `< 1`        → 3 significant figures (e.g. "0.000123")
 */
export function formatStrikeValue(strike: bigint): string {
  const n = Number(formatUnits(strike, 18));
  if (!Number.isFinite(n)) return "—";
  if (n >= 100) return n.toLocaleString("en-US", { maximumFractionDigits: 0 });
  if (n >= 1) return n.toLocaleString("en-US", { maximumFractionDigits: 2 });
  return n.toLocaleString("en-US", { maximumSignificantDigits: 3 });
}

/** Convenience: option → display string in one call. */
export function formatOptionStrike(opt: Pick<TradableOption, "strike" | "isPut">): string {
  return formatStrikeValue(displayStrike(opt));
}
