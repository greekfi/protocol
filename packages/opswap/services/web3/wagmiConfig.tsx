import { wagmiConnectors } from "./wagmiConnectors";
import { createClient, fallback, http } from "viem";
import { createConfig } from "wagmi";
import scaffoldConfig from "~~/scaffold.config";

const { targetNetworks, rpcOverrides } = scaffoldConfig;

export const enabledChains = targetNetworks;

export const wagmiConfig = createConfig({
  chains: enabledChains,
  // connectors: wagmiConnectors,
  ssr: true,
  client: ({ chain }) => {
    // Use RPC override if available, otherwise use default
    const rpcUrl = rpcOverrides?.[chain.id as keyof typeof rpcOverrides];

    return createClient({
      chain,
      transport: fallback([http(rpcUrl)]),
      pollingInterval: scaffoldConfig.pollingInterval,
    });
  },
});
