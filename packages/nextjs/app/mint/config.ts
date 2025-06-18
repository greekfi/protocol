import { createConfig, http } from "wagmi";
import { arbitrum, base, baseSepolia, mainnet, optimism, plume, plumeTestnet, sepolia } from "wagmi/chains";
import { Chain } from "wagmi/chains";
import { create } from "zustand";

// Define localhost chain
export const localhost = {
  id: 31337,
  name: "Localhost",
  nativeCurrency: {
    decimals: 18,
    name: "Ether",
    symbol: "ETH",
  },
  rpcUrls: {
    default: { http: ["http://127.0.0.1:8545"] },
    public: { http: ["http://127.0.0.1:8545"] },
  },
} as const satisfies Chain;

// Define available chains
export const availableChains = [
  localhost,
  sepolia,
  mainnet,
  arbitrum,
  optimism,
  base,
  baseSepolia,
  plume,
  plumeTestnet,
];

// Create a store to manage the current chain
interface ChainState {
  currentChain: Chain;
  setCurrentChain: (chain: Chain) => void;
}

export const useChainStore = create<ChainState>(set => ({
  currentChain: localhost,
  setCurrentChain: chain => set({ currentChain: chain }),
}));

// Create the initial config
export const config = createConfig({
  chains: [localhost, sepolia, mainnet],
  transports: {
    [localhost.id]: http(),
    [sepolia.id]: http(process.env.ALCHEMY_SEPOLIA_URL),
    [mainnet.id]: http(process.env.ALCHEMY_MAINNET_URL),
  },
});
