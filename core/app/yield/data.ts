/**
 * /yield page data — now a thin view over the canonical token list at
 * `core/app/data/tokens.ts`. Kept as a separate module so /yield's
 * imports don't need to churn, but every constant here is derived from
 * the single source of truth.
 *
 * The CALL_UNDERLYINGS / PUT_UNDERLYINGS / STABLECOINS exports are
 * chain-agnostic universes. Pages filter to "exists on current chain"
 * via the chain-aware helpers in tokens.ts (or via TokenGrid, which
 * does the intersection internally with useTokenMap).
 */

import { TOKENS } from "../data/tokens";
import type { UnderlyingToken } from "../components/options/TokenGrid";

export type { AprRange, UnderlyingToken } from "../components/options/TokenGrid";
export { formatAprRange } from "../components/options/TokenGrid";

export type Stablecoin = {
  symbol: string;
  name: string;
  color: string;
};

// Calls and puts share the same underlying universe today (APR ranges too;
// if they ever diverge, split via t.apr.calls / t.apr.puts on the canonical
// Token entry).
const UNDERLYINGS_VIEW: UnderlyingToken[] = TOKENS.filter(t => t.kind === "underlying").map(t => ({
  symbol: t.symbol,
  name: t.name,
  color: t.color,
  apr: t.apr,
}));

export const CALL_UNDERLYINGS: UnderlyingToken[] = UNDERLYINGS_VIEW;
export const PUT_UNDERLYINGS: UnderlyingToken[] = UNDERLYINGS_VIEW;

// Stablecoins users can deposit to write covered puts.
export const STABLECOINS: Stablecoin[] = TOKENS.filter(t => t.kind === "stable").map(t => ({
  symbol: t.symbol,
  name: t.name,
  color: t.color,
}));
