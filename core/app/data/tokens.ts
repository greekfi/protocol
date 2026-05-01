/**
 * Canonical token list for the entire frontend. One file, one source of
 * truth — used by /mint (full picker), /trade (TokenGrid + balances +
 * approvals), /yield (TokenGrid + stablecoin tabs), and any other surface
 * that needs to ask "which tokens exist on chain X?".
 *
 * Each token has display metadata (symbol, name, colour, optional APR) plus
 * a per-chain address map. A token "exists on chain X" iff it has a non-null
 * address for that chainId. New chain support = add an address to each
 * token's `addresses`. New token = append a row.
 *
 * `kind` partitions the table for chain-agnostic UIs:
 *   - "underlying" — the volatile asset an option is on (WETH, WBTC, AAVE…).
 *     For calls this is the collateral; for puts it's the consideration.
 *     Driven by /trade's TokenGrid and /yield's covered-call/put picker.
 *   - "stable"     — the quote asset (USDC, USDT…). Drives /yield's
 *     stablecoin tabs and shows up as the "consideration" token.
 *   - "other"      — wrapped variants, yield-bearing stables, etc. Shown
 *     in /mint's full-picker dropdown so users can mint against arbitrary
 *     ERC20 pairs, but hidden from /trade and /yield where the structured
 *     UI only makes sense for canonical underlyings.
 */

export type TokenKind = "underlying" | "stable" | "other";

export interface Token {
  symbol: string;
  name: string;
  decimals: number;
  /** Tailwind bg-* class used as a fallback when the /tokens/<symbol>.png is missing. */
  color: string;
  kind: TokenKind;
  /** Per-chain ERC20 addresses. Missing keys = not deployed on that chain. */
  addresses: Partial<Record<number, `0x${string}`>>;
  /** Optional yield estimate; only meaningful for underlyings, only rendered on /yield. */
  apr?: { min: number; max: number };
}

// Chain IDs for readability. Keep in sync with scaffold.config.ts targetNetworks.
const ETH = 1;
const UNICHAIN = 130;
const BASE = 8453;
const ARBITRUM = 42161;
const INK = 57073;

export const TOKENS: Token[] = [
  // ============ Underlyings ============
  {
    symbol: "WETH",
    name: "Wrapped Ether",
    decimals: 18,
    color: "bg-indigo-500",
    kind: "underlying",
    apr: { min: 9, max: 18 },
    addresses: {
      [ETH]: "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2",
      [UNICHAIN]: "0x4200000000000000000000000000000000000006",
      [BASE]: "0x4200000000000000000000000000000000000006",
      [ARBITRUM]: "0x82aF49447D8a07e3bd95BD0d56f35241523fBab1",
    },
  },
  {
    symbol: "WBTC",
    name: "Wrapped Bitcoin",
    decimals: 8,
    color: "bg-amber-500",
    kind: "underlying",
    apr: { min: 7, max: 14 },
    addresses: {
      [ETH]: "0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599",
      [ARBITRUM]: "0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f",
    },
  },
  {
    symbol: "cbBTC",
    name: "Coinbase Wrapped BTC",
    decimals: 8,
    color: "bg-orange-500",
    kind: "underlying",
    apr: { min: 7, max: 14 },
    addresses: {
      [ETH]: "0xcbB7C0000aB88B473b1f5aFd9ef808440eed33Bf",
      [BASE]: "0xcbB7C0000aB88B473b1f5aFd9ef808440eed33Bf",
    },
  },
  {
    symbol: "AAVE",
    name: "Aave",
    decimals: 18,
    color: "bg-purple-500",
    kind: "underlying",
    apr: { min: 12, max: 24 },
    addresses: {
      [ARBITRUM]: "0xba5DdD1f9d7F570dc94a51479a000E3BCE967196",
    },
  },
  {
    symbol: "UNI",
    name: "Uniswap",
    decimals: 18,
    color: "bg-pink-500",
    kind: "underlying",
    apr: { min: 10, max: 22 },
    addresses: {
      [ETH]: "0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984",
      [UNICHAIN]: "0x8f187aa05619a017077f5308904739877ce9ea21",
      [BASE]: "0xfb3CB973B2a9e2E09746393C59e7FB0d5189d290",
      [ARBITRUM]: "0xFa7F8980b0f1E64A2062791cc3b0871572f1F7f0",
    },
  },
  {
    symbol: "MORPHO",
    name: "Morpho",
    decimals: 18,
    color: "bg-blue-500",
    kind: "underlying",
    apr: { min: 11, max: 21 },
    addresses: {
      [ARBITRUM]: "0x40bd670A58238E6e230c430BBb5cE6EC0D40Df48",
    },
  },

  // ============ Stables ============
  {
    symbol: "USDC",
    name: "USD Coin",
    decimals: 6,
    color: "bg-sky-500",
    kind: "stable",
    addresses: {
      [ETH]: "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48",
      [UNICHAIN]: "0x078d782b760474a361dda0af3839290b0ef57ad6",
      [BASE]: "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913",
      [ARBITRUM]: "0xaf88d065e77c8cC2239327C5EDb3A432268e5831",
    },
  },
  {
    symbol: "USDT",
    name: "Tether",
    decimals: 6,
    color: "bg-emerald-500",
    kind: "stable",
    addresses: {
      [BASE]: "0xfde4C96c8593536E31F229EA8f37b2ADa2699bb2",
      [ARBITRUM]: "0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9",
    },
  },
  {
    symbol: "USDT0",
    name: "USDT0",
    decimals: 6,
    color: "bg-teal-500",
    kind: "stable",
    addresses: {
      [UNICHAIN]: "0x9151434b16b9763660705744891fa906f660ecc5",
    },
  },
  {
    symbol: "DAI",
    name: "Dai",
    decimals: 18,
    color: "bg-yellow-500",
    kind: "stable",
    addresses: {
      [ETH]: "0x6B175474E89094C44Da98b954EedeAC495271d0F",
    },
  },

  // ============ Other (shown in /mint's free-form picker only) ============
  {
    symbol: "wstETH",
    name: "Wrapped stETH",
    decimals: 18,
    color: "bg-indigo-400",
    kind: "other",
    addresses: {
      [UNICHAIN]: "0xc02fe7317d4eb8753a02c35fe019786854a92001",
      [BASE]: "0xc1CBa3fCea344f92D9239c08C0568f6F2F0ee452",
    },
  },
  {
    symbol: "weETH",
    name: "ether.fi Wrapped",
    decimals: 18,
    color: "bg-indigo-300",
    kind: "other",
    addresses: {
      [UNICHAIN]: "0x7dcc39b4d1c53cb31e1abc0e358b43987fef80f7",
      [BASE]: "0x04C0599Ae5A44757c0af6F9eC3b93da8976c150A",
    },
  },
  {
    symbol: "ezETH",
    name: "Renzo Restaked ETH",
    decimals: 18,
    color: "bg-indigo-300",
    kind: "other",
    addresses: {
      [UNICHAIN]: "0x2416092f143378750bb29b79ed961ab195cceea5",
      [BASE]: "0x2416092f143378750bb29b79eD961ab195CcEea5",
    },
  },
  {
    symbol: "rsETH",
    name: "KelpDAO Restaked ETH",
    decimals: 18,
    color: "bg-indigo-300",
    kind: "other",
    addresses: { [UNICHAIN]: "0xc3eacf0612346366db554c991d7858716db09f58" },
  },
  {
    symbol: "osETH",
    name: "StakeWise osETH",
    decimals: 18,
    color: "bg-indigo-300",
    kind: "other",
    addresses: { [ETH]: "0xf1C9acDc66974dFB6dEcB12aA385b9cD01190E38" },
  },
  {
    symbol: "sUSDC",
    name: "Sky Savings USDC",
    decimals: 6,
    color: "bg-sky-400",
    kind: "other",
    addresses: {
      [UNICHAIN]: "0x14d9143becc348920b68d123687045db49a016c6",
      [BASE]: "0x3128a0F7f0ea68E7B7c9B00AFa7E41045828e858",
    },
  },
  {
    symbol: "sUSDS",
    name: "Sky Savings USDS",
    decimals: 6,
    color: "bg-sky-400",
    kind: "other",
    addresses: {
      [UNICHAIN]: "0xa06b10db9f390990364a3984c04fadf1c13691b5",
      [BASE]: "0xa06b10db9f390990364a3984c04fadf1c13691b5",
    },
  },
  {
    symbol: "USDS",
    name: "Sky USDS",
    decimals: 6,
    color: "bg-sky-400",
    kind: "other",
    addresses: {
      [UNICHAIN]: "0x7e10036acc4b56d4dfca3b77810356ce52313f9c",
      [BASE]: "0x5875eEE11Cf8398102FdAd704C9E96607675467a",
    },
  },
  {
    symbol: "kBTC",
    name: "Kraken BTC",
    decimals: 8,
    color: "bg-amber-400",
    kind: "other",
    addresses: { [UNICHAIN]: "0x73e0c0d45e048d25fc26fa3159b0aa04bfa4db98" },
  },
  {
    symbol: "PAXG",
    name: "PAX Gold",
    decimals: 18,
    color: "bg-yellow-400",
    kind: "other",
    addresses: {
      [ETH]: "0x45804880De22913dAFE09f4980848ECE6EcbAf78",
      [ARBITRUM]: "0xfEb4DfC8C4Cf7Ed305bb08065D08eC6ee6728429",
    },
  },
  {
    symbol: "XAUt",
    name: "Tether Gold",
    decimals: 6,
    color: "bg-yellow-400",
    kind: "other",
    addresses: {
      [ETH]: "0x68749665FF8D2d112Fa859AA293F07A622782F38",
      [ARBITRUM]: "0x40461291347e1ecbb09499F3371d3F17F10D7159",
    },
  },
];

// ============ Helpers — chain-aware lookups ============

/** All tokens deployed on `chainId`, in the order they appear in TOKENS. */
export function tokensForChain(chainId: number): Token[] {
  return TOKENS.filter(t => t.addresses[chainId]);
}

export function underlyingsForChain(chainId: number): Token[] {
  return tokensForChain(chainId).filter(t => t.kind === "underlying");
}

export function stablesForChain(chainId: number): Token[] {
  return tokensForChain(chainId).filter(t => t.kind === "stable");
}

export function tokenBySymbol(chainId: number, symbol: string): Token | undefined {
  const t = TOKENS.find(x => x.symbol === symbol);
  return t && t.addresses[chainId] ? t : undefined;
}

export function tokenByAddress(chainId: number, address: string): Token | undefined {
  const lower = address.toLowerCase();
  return TOKENS.find(t => t.addresses[chainId]?.toLowerCase() === lower);
}

/**
 * Adapter for callers that want the legacy `{address, symbol, decimals}`
 * shape with the address resolved against the current chain.
 */
export interface AddressedToken {
  address: string;
  symbol: string;
  decimals: number;
}
export function addressedTokensForChain(chainId: number): AddressedToken[] {
  return tokensForChain(chainId).map(t => ({
    address: t.addresses[chainId] as string,
    symbol: t.symbol,
    decimals: t.decimals,
  }));
}
