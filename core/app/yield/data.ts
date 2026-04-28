// Placeholder data for the /yield app — swap with on-chain / market-maker data later.

import type { UnderlyingToken } from "../components/options/TokenGrid";

// Re-export the shared types so existing /yield call sites keep working.
export type { AprRange, UnderlyingToken } from "../components/options/TokenGrid";
export { formatAprRange } from "../components/options/TokenGrid";

export type Stablecoin = {
  symbol: string;
  name: string;
  color: string;
};

// Covered-call underlyings — user writes calls, keeps the premium.
export const CALL_UNDERLYINGS: UnderlyingToken[] = [
  { symbol: "WETH", name: "Wrapped Ether", color: "bg-indigo-500", apr: { min: 9, max: 18 } },
  { symbol: "WBTC", name: "Wrapped Bitcoin", color: "bg-amber-500", apr: { min: 7, max: 14 } },
  { symbol: "cbBTC", name: "Coinbase Wrapped BTC", color: "bg-orange-500", apr: { min: 7, max: 14 } },
  { symbol: "AAVE", name: "Aave", color: "bg-purple-500", apr: { min: 12, max: 24 } },
  { symbol: "UNI", name: "Uniswap", color: "bg-pink-500", apr: { min: 10, max: 22 } },
  { symbol: "MORPHO", name: "Morpho", color: "bg-blue-500", apr: { min: 11, max: 21 } },
];

// Stablecoins users can deposit to write covered puts.
export const STABLECOINS: Stablecoin[] = [
  { symbol: "USDC", name: "USD Coin", color: "bg-sky-500" },
  { symbol: "USDT", name: "Tether", color: "bg-emerald-500" },
  { symbol: "USDT0", name: "USDT0", color: "bg-teal-500" },
  { symbol: "DAI", name: "Dai", color: "bg-yellow-500" },
];

// Covered-put underlyings — APRs may differ per (stablecoin, token) pair once wired up;
// for now we keep a single range per token.
export const PUT_UNDERLYINGS: UnderlyingToken[] = [
  { symbol: "WETH", name: "Wrapped Ether", color: "bg-indigo-500", apr: { min: 8, max: 16 } },
  { symbol: "WBTC", name: "Wrapped Bitcoin", color: "bg-amber-500", apr: { min: 6, max: 13 } },
  { symbol: "cbBTC", name: "Coinbase Wrapped BTC", color: "bg-orange-500", apr: { min: 6, max: 13 } },
  { symbol: "AAVE", name: "Aave", color: "bg-purple-500", apr: { min: 11, max: 22 } },
  { symbol: "UNI", name: "Uniswap", color: "bg-pink-500", apr: { min: 9, max: 20 } },
  { symbol: "MORPHO", name: "Morpho", color: "bg-blue-500", apr: { min: 10, max: 19 } },
];

