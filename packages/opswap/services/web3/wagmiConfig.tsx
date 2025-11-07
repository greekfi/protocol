import { wagmiConnectors } from "./wagmiConnectors";
import { createClient, fallback, http } from "viem";
import { createConfig } from "wagmi";
import scaffoldConfig from "~~/scaffold.config";

const { targetNetworks } = scaffoldConfig;

export const enabledChains = targetNetworks;

export const wagmiConfig = createConfig({
  chains: enabledChains,
  connectors: wagmiConnectors,
  ssr: true,
  client: ({ chain }) => {
    return createClient({
      chain,
      transport: fallback([http()]),
      pollingInterval: scaffoldConfig.pollingInterval,
    });
  },
});
