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

// Foundry must come *last*. wagmi treats `chains[0]` as the default chain that
// contract reads / writes use when no chainId hint is passed. Anything else
// would route default reads to http://127.0.0.1:8545 (anvil) on localhost dev,
// even when the wallet is on Arbitrum — `ERR_CONNECTION_REFUSED` everywhere.
const realChains = targetNetworks.filter(c => c.id !== chains.foundry.id);
const filteredNetworks = isLocalhost ? [...realChains, chains.foundry] : realChains;

// `createConfig` requires at least one chain. Fall back to `targetNetworks` (which
// includes Foundry) on the off-chance every public chain was removed; in practice
// `filteredNetworks` always contains base + arbitrum.
const enabledNetworks = filteredNetworks.length > 0 ? filteredNetworks : targetNetworks;

export const enabledChains = enabledNetworks;

// wagmi's `createConfig` is `<const chains extends readonly [Chain, ...Chain[]]>`,
// so even when the argument is pre-typed `readonly Chain[]` it re-infers
// literal types (transaction.type discriminants like "legacy"/"eip7702",
// formatters, contract refs) and chokes on the heterogeneous tuple our
// targetNetworks produces (Arbitrum + Base + Ink + Foundry don't agree).
// No runtime issue — wagmi accepts any Chain-shaped object — purely a
// TS narrowing bug. Suppress the call-site error.
// @ts-ignore wagmi createConfig generic infers literal types that don't unify across mixed-EVM-version chains
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
