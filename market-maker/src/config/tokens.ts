// market-maker/src/config/tokens.ts

export interface TokenConfig {
  address: string;
  symbol: string;
  decimals: number;
  name: string;
}

// Token addresses per chain
export const TOKENS: Record<number, Record<string, TokenConfig>> = {
  // === ETHEREUM MAINNET ===
  1: {
    WETH: {
      address: "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2",
      symbol: "WETH",
      decimals: 18,
      name: "Wrapped Ether",
    },
    USDC: {
      address: "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48",
      symbol: "USDC",
      decimals: 6,
      name: "USD Coin",
    },
    USDT: {
      address: "0xdAC17F958D2ee523a2206206994597C13D831ec7",
      symbol: "USDT",
      decimals: 6,
      name: "Tether USD",
    },
    DAI: {
      address: "0x6B175474E89094C44Da98b954EescdeCB5BBCFA0",
      symbol: "DAI",
      decimals: 18,
      name: "Dai Stablecoin",
    },
    WBTC: {
      address: "0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599",
      symbol: "WBTC",
      decimals: 8,
      name: "Wrapped BTC",
    },
  },

  // === BASE MAINNET ===
  8453: {
    WETH: {
      address: "0x4200000000000000000000000000000000000006",
      symbol: "WETH",
      decimals: 18,
      name: "Wrapped Ether",
    },
    USDC: {
      address: "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913",
      symbol: "USDC",
      decimals: 6,
      name: "USD Coin",
    },
    USDbC: {
      address: "0xd9aAEc86B65D86f6A7B5B1b0c42FFA531710b6CA",
      symbol: "USDbC",
      decimals: 6,
      name: "USD Base Coin (Bridged)",
    },
    cbETH: {
      address: "0x2Ae3F1Ec7F1F5012CFEab0185bfc7aa3cf0DEc22",
      symbol: "cbETH",
      decimals: 18,
      name: "Coinbase Wrapped Staked ETH",
    },
  },

  // === ARBITRUM ONE ===
  42161: {
    WETH: {
      address: "0x82aF49447D8a07e3bd95BD0d56f35241523fBab1",
      symbol: "WETH",
      decimals: 18,
      name: "Wrapped Ether",
    },
    USDC: {
      address: "0xaf88d065e77c8cC2239327C5EDb3A432268e5831",
      symbol: "USDC",
      decimals: 6,
      name: "USD Coin",
    },
    "USDC.e": {
      address: "0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8",
      symbol: "USDC.e",
      decimals: 6,
      name: "USD Coin (Bridged)",
    },
    ARB: {
      address: "0x912CE59144191C1204E64559FE8253a0e49E6548",
      symbol: "ARB",
      decimals: 18,
      name: "Arbitrum",
    },
  },

  // === UNICHAIN MAINNET ===
  130: {
    WETH: {
      address: "0x4200000000000000000000000000000000000006",
      symbol: "WETH",
      decimals: 18,
      name: "Wrapped Ether",
    },
    USDC: {
      address: "0x078D888E40faAe0f32594342c85940AF0b45DA6D",
      symbol: "USDC",
      decimals: 6,
      name: "USD Coin",
    },
  },

  // === SEPOLIA TESTNET ===
  11155111: {
    WETH: {
      address: "0x7b79995e5f793A07Bc00c21412e50Ecae098E7f9",
      symbol: "WETH",
      decimals: 18,
      name: "Wrapped Ether",
    },
    USDC: {
      address: "0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238",
      symbol: "USDC",
      decimals: 6,
      name: "USD Coin",
    },
  },

  // === BASE SEPOLIA ===
  84532: {
    WETH: {
      address: "0x4200000000000000000000000000000000000006",
      symbol: "WETH",
      decimals: 18,
      name: "Wrapped Ether",
    },
    USDC: {
      address: "0x036CbD53842c5426634e7929541eC2318f3dCF7e",
      symbol: "USDC",
      decimals: 6,
      name: "USD Coin",
    },
  },

  // === UNICHAIN SEPOLIA ===
  1301: {
    WETH: {
      address: "0x4200000000000000000000000000000000000006",
      symbol: "WETH",
      decimals: 18,
      name: "Wrapped Ether",
    },
    USDC: {
      address: "0x31d0220469e10c4E71834a79b1f276d740d3768F",
      symbol: "USDC",
      decimals: 6,
      name: "USD Coin",
    },
  },

  // === ANVIL (LOCAL) ===
  31337: {
    WETH: {
      address: "0x...",  // Deployed by test setup
      symbol: "WETH",
      decimals: 18,
      name: "Wrapped Ether",
    },
    USDC: {
      address: "0x...",  // Deployed by test setup
      symbol: "USDC",
      decimals: 6,
      name: "USD Coin",
    },
  },
};

export function getToken(chainId: number, symbol: string): TokenConfig {
  const chainTokens = TOKENS[chainId];
  if (!chainTokens) throw new Error(`No tokens configured for chain ${chainId}`);
  const token = chainTokens[symbol];
  if (!token) throw new Error(`Token ${symbol} not found on chain ${chainId}`);
  return token;
}

export function getTokenByAddress(chainId: number, address: string): TokenConfig | undefined {
  const chainTokens = TOKENS[chainId];
  if (!chainTokens) return undefined;
  return Object.values(chainTokens).find(
    (t) => t.address.toLowerCase() === address.toLowerCase()
  );
}
