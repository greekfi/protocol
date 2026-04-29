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
  // The networks on which the protocol is deployed. Order matters: wagmi
  // treats the first chain as the default for contract reads when no chainId
  // hint is passed. Arbitrum is first so unconnected users (and stray
  // wagmi `useReadContract` calls) hit a real chain instead of foundry. The
  // wagmiConfig moves foundry to the *end* of the list on localhost (and
  // strips it elsewhere), so localhost dev still has it available in the
  // chain switcher without ever being the default.
  // Mainnet is intentionally absent — no Greek factory on Ethereum yet.
  targetNetworks: [chains.arbitrum, chains.base, chains.foundry],
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
