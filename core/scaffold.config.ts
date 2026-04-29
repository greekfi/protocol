import * as chains from "viem/chains";

export type BaseConfig = {
  targetNetworks: readonly chains.Chain[];
  pollingInterval: number;
  alchemyApiKey: string;
  rpcOverrides?: Record<number, string>;
  walletConnectProjectId: string;
  onlyLocalBurnerWallet: boolean;
};

export type ScaffoldConfig = BaseConfig;

export const DEFAULT_ALCHEMY_API_KEY = "oKxs-03sij-U_N0iOlrSsZFr29-IqbuF";

// Shared Alchemy default key is heavily rate-limited (often 403s). When the user
// hasn't supplied their own NEXT_PUBLIC_ALCHEMY_API_KEY, fall back to PublicNode —
// free, no auth, generous limits — instead of a broken Alchemy endpoint.
const userAlchemyKey = process.env.NEXT_PUBLIC_ALCHEMY_API_KEY;
const baseRpc = userAlchemyKey
  ? `https://base-mainnet.g.alchemy.com/v2/${userAlchemyKey}`
  : "https://base-rpc.publicnode.com";
const arbitrumRpc = userAlchemyKey
  ? `https://arb-mainnet.g.alchemy.com/v2/${userAlchemyKey}`
  : "https://arbitrum-one-rpc.publicnode.com";

const scaffoldConfig = {
  // The networks on which the protocol is deployed. Order matters: the first
  // non-foundry chain is wagmi's default when no wallet is connected (so a user
  // landing on /trade without a wallet sees Arbitrum's options). Mainnet is
  // intentionally absent — there's no Greek factory on Ethereum yet, and
  // including it caused chain-1 fallbacks to scan from genesis (see #69).
  // `foundry` is filtered out at runtime in wagmiConfig when not on localhost.
  targetNetworks: [chains.foundry, chains.arbitrum, chains.base],
  // The interval at which your front-end polls the RPC servers for new data (it has no effect if you only target the local network (default is 4000))
  pollingInterval: 30000,
  // This is ours Alchemy's default API key.
  // You can get your own at https://dashboard.alchemyapi.io
  // It's recommended to store it in an env variable:
  // .env.local for local testing, and in the Vercel/system env config for live apps.
  alchemyApiKey: userAlchemyKey || DEFAULT_ALCHEMY_API_KEY,
  // If you want to use a different RPC for a specific network, you can add it here.
  // The key is the chain ID, and the value is the HTTP RPC URL
  rpcOverrides: {
    [chains.base.id]: baseRpc,
    [chains.arbitrum.id]: arbitrumRpc,
  },
  // This is ours WalletConnect's default project ID.
  // You can get your own at https://cloud.walletconnect.com
  // It's recommended to store it in an env variable:
  // .env.local for local testing, and in the Vercel/system env config for live apps.
  walletConnectProjectId: process.env.NEXT_PUBLIC_WALLET_CONNECT_PROJECT_ID || "3a8170812b534d0ff9d794f19a901d64",
  onlyLocalBurnerWallet: true,
} as const satisfies ScaffoldConfig;

export default scaffoldConfig;
