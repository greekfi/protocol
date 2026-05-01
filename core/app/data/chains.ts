/**
 * Per-chain magic-address helpers. Anywhere a hook would otherwise inline
 * a `Record<number, string>` map of "USDC by chain" or "Bebop router by
 * chain" should call into this module instead — single source of truth,
 * changes ripple to every consumer.
 *
 * Token addresses themselves live in `core/app/data/tokens.ts`; this file
 * just exposes the named lookups callers care about (USDC, the Bebop
 * settlement router, the block explorer base URL, …).
 */

import type { Address } from "viem";
import { tokenBySymbol } from "./tokens";

/**
 * Bebop's universal settlement router — same address on every EVM chain
 * Bebop supports today, by their design (CREATE2 deployment with the same
 * salt + bytecode). If a future chain breaks that invariant, override here.
 */
const BEBOP_ROUTER: Address = "0xbbbbbBB520d69a9775E85b458C58c648259FAD5F";

export function bebopRouterFor(_chainId: number): Address {
  return BEBOP_ROUTER;
}

/**
 * Canonical USDC for trade-quote pricing. Resolves via the unified token
 * table; chains without a USDC entry return undefined (caller decides how
 * to handle — usually disable the trade UI).
 */
export function usdcFor(chainId: number): Address | undefined {
  const t = tokenBySymbol(chainId, "USDC");
  return t?.addresses[chainId];
}

/**
 * True when `address` is the canonical USDC on `chainId`. Used by the
 * pricing-stream pair parser to identify the non-USDC side of a pair
 * string regardless of which chain the pair came from.
 */
export function isUsdc(chainId: number, address: string): boolean {
  const u = usdcFor(chainId);
  return !!u && u.toLowerCase() === address.toLowerCase();
}

/** Block-explorer base URL per chain — for tx-hash links. */
const EXPLORERS: Record<number, string> = {
  1: "https://etherscan.io",
  130: "https://uniscan.xyz",
  8453: "https://basescan.org",
  42161: "https://arbiscan.io",
  57073: "https://explorer.inkonchain.com",
};

export function explorerFor(chainId: number): string | undefined {
  return EXPLORERS[chainId];
}

export function txUrl(chainId: number, txHash: string): string | undefined {
  const base = explorerFor(chainId);
  return base ? `${base}/tx/${txHash}` : undefined;
}
