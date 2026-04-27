import { createClient, fallback, http } from "viem";
import * as chains from "viem/chains";
import { createConfig } from "wagmi";
import scaffoldConfig from "~~/scaffold.config";

const { targetNetworks, rpcOverrides } = scaffoldConfig;

// Show Foundry/localhost only when the app itself is being served from localhost.
// During SSR `window` is undefined → treat as remote → hide Foundry. Most users hit a
// deployed origin, so this matches their initial HTML; localhost developers see Foundry
// after client hydration, which is acceptable since the dropdown is interaction-driven.
const isLocalhost =
  typeof window !== "undefined" &&
  ["localhost", "127.0.0.1", "0.0.0.0"].includes(window.location.hostname);

const filteredNetworks = isLocalhost
  ? targetNetworks
  : (targetNetworks.filter(c => c.id !== chains.foundry.id) as readonly chains.Chain[]);

// `createConfig` requires at least one chain. Fall back to `targetNetworks` (which
// includes Foundry) on the off-chance every public chain was removed; in practice
// `filteredNetworks` always contains base + arbitrum.
const enabledNetworks = filteredNetworks.length > 0 ? filteredNetworks : targetNetworks;

export const enabledChains = enabledNetworks;

export const wagmiConfig = createConfig({
  chains: enabledChains as unknown as readonly [chains.Chain, ...chains.Chain[]],
  ssr: true,
  client: ({ chain }) => {
    const rpcUrl = rpcOverrides?.[chain.id as keyof typeof rpcOverrides];

    return createClient({
      chain,
      transport: fallback([http(rpcUrl)]),
      pollingInterval: scaffoldConfig.pollingInterval,
    });
  },
});
