import { useQuery } from "@tanstack/react-query";

// Symbol → CoinGecko ID. WBTC / cbBTC are 1:1 wrappers so they share BTC's
// price; same for WETH / ETH.
const COINGECKO_IDS: Record<string, string> = {
  WETH: "ethereum",
  ETH: "ethereum",
  WBTC: "bitcoin",
  CBBTC: "bitcoin",
  AAVE: "aave",
  UNI: "uniswap",
  MORPHO: "morpho",
};

const STABLES = new Set(["USDC", "USDT", "USDT0", "DAI"]);

/**
 * Spot price (USD) for a given token symbol. Sourced from DeFiLlama's coins
 * API via CoinGecko IDs — chain-agnostic and independent of the protocol's
 * market-maker so it works wherever the chain selector is pointed.
 *
 * Stablecoins return 1 without making a request. Unknown symbols return
 * `undefined` — callers should treat that as "no filter / no display".
 */
export function useTokenSpot(symbol: string | null | undefined): number | undefined {
  const norm = symbol?.toUpperCase();
  const id = norm ? COINGECKO_IDS[norm] : undefined;

  const { data } = useQuery({
    queryKey: ["coingecko-spot", id],
    queryFn: async () => {
      if (!id) return null;
      const res = await fetch(`https://coins.llama.fi/prices/current/coingecko:${id}`);
      if (!res.ok) return null;
      const body = (await res.json()) as { coins?: Record<string, { price?: number }> };
      const price = body.coins?.[`coingecko:${id}`]?.price;
      return typeof price === "number" && Number.isFinite(price) && price > 0 ? price : null;
    },
    enabled: Boolean(id),
    staleTime: 30_000,
    refetchInterval: 30_000,
  });

  if (norm && STABLES.has(norm)) return 1;
  return data ?? undefined;
}
