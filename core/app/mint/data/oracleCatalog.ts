// Curated list of suggested oracle sources (Uniswap v3 pools) per chain. The
// /mint Create form surfaces these as suggestions in the Oracle input, but
// the field is a free-form text input so users can type any address. Picked
// by depth of liquidity rather than aiming for full coverage; deeper pools
// produce more manipulation-resistant TWAPs.

export type OracleSuggestion = {
  /** Pool address used as the oracle source. */
  address: `0x${string}`;
  /** Token symbols on either side of the pool, used to filter suggestions
   *  to the option's (collateral, consideration) pair. Order doesn't matter. */
  pair: [string, string];
  /** Human label shown in the suggestion dropdown. */
  label: string;
};

/**
 * Suggestions keyed by chain ID. Each chain only carries pools that actually
 * exist and have meaningful liquidity on that chain — the Base set isn't
 * mainnet's set, etc. Update as deeper pools appear.
 */
export const ORACLE_CATALOG: Record<number, OracleSuggestion[]> = {
  // Ethereum mainnet
  1: [
    {
      address: "0x88e6A0c2dDD26FEEb64F039a2c41296FcB3f5640",
      pair: ["WETH", "USDC"],
      label: "WETH/USDC · Uniswap v3 · 0.05%",
    },
    {
      address: "0x99ac8cA7087fA4A2A1FB6357269965A2014ABc35",
      pair: ["WBTC", "USDC"],
      label: "WBTC/USDC · Uniswap v3 · 0.30%",
    },
    {
      address: "0x4585FE77225b41b697C938B018E2Ac67Ac5a20c0",
      pair: ["WBTC", "WETH"],
      label: "WBTC/WETH · Uniswap v3 · 0.05%",
    },
  ],

  // Base
  8453: [
    {
      address: "0xd0b53D9277642d899DF5C87A3966A349A798F224",
      pair: ["WETH", "USDC"],
      label: "WETH/USDC · Uniswap v3 · 0.05%",
    },
  ],

  // Arbitrum
  42161: [
    {
      address: "0xC6962004f452bE9203591991D15f6b388e09E8D0",
      pair: ["WETH", "USDC"],
      label: "WETH/USDC · Uniswap v3 · 0.05%",
    },
    {
      address: "0x2f5e87C9312fa29aed5c179E456625D79015299c",
      pair: ["WBTC", "WETH"],
      label: "WBTC/WETH · Uniswap v3 · 0.05%",
    },
  ],

  // Foundry / local — no canonical pools, leave empty.
  31337: [],
};

/** Case-insensitive symbol-pair match in either direction. */
export function pairMatches(suggestion: OracleSuggestion, a: string | undefined, b: string | undefined): boolean {
  if (!a || !b) return true; // before tokens are picked, show everything
  const sa = suggestion.pair[0].toLowerCase();
  const sb = suggestion.pair[1].toLowerCase();
  const ua = a.toLowerCase();
  const ub = b.toLowerCase();
  return (sa === ua && sb === ub) || (sa === ub && sb === ua);
}
