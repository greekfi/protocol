#!/usr/bin/env node
import "dotenv/config";
import { Pricer } from "./pricing/pricer";
import { SpotFeed } from "./pricing/spotFeed";
import { startDirectMode } from "./modes/direct";
import { getCurrentChainId } from "./config/client";
import { getTokenByAddress } from "./config/tokens";

/**
 * Map a collateral-token symbol to the spot-feed symbol used for pricing.
 * BTC variants (WBTC, cbBTC, …) all reference the BTC spot. ETH variants
 * (WETH, stETH, wstETH, …) all reference the ETH spot. Add more here as the
 * protocol supports new underlyings.
 */
function feedSymbolFor(tokenSymbol: string | undefined): string | undefined {
  if (!tokenSymbol) return undefined;
  const s = tokenSymbol.toUpperCase();
  if (s === "WETH" || s === "ETH" || s.endsWith("ETH")) return "ETH";
  if (s === "WBTC" || s === "BTC" || s === "CBBTC" || s.endsWith("BTC")) return "BTC";
  return undefined; // unknown — pricer will skip / no spot
}

async function main() {
  console.log("Starting market-maker in DIRECT mode");

  const spotFeed = new SpotFeed();
  const smileEnv = {
    skew: process.env.IV_SKEW !== undefined ? parseFloat(process.env.IV_SKEW) : undefined,
    curvature: process.env.IV_CURVATURE !== undefined ? parseFloat(process.env.IV_CURVATURE) : undefined,
    termRef:
      process.env.IV_TERM_REF_DAYS !== undefined
        ? parseFloat(process.env.IV_TERM_REF_DAYS) / 365
        : undefined,
    putOffset:
      process.env.IV_PUT_OFFSET !== undefined ? parseFloat(process.env.IV_PUT_OFFSET) : undefined,
  };
  const smile = Object.fromEntries(Object.entries(smileEnv).filter(([, v]) => v !== undefined));

  const pricer = new Pricer({
    spotFeed,
    defaultIV: parseFloat(process.env.DEFAULT_IV || "0.8"),
    riskFreeRate: parseFloat(process.env.RISK_FREE_RATE || "0.05"),
    smile,
  });
  spotFeed.start();

  spotFeed.onPriceUpdate((symbol, price) => {
    pricer.setSpotPrice(symbol, price);
  });

  console.log("Loading option metadata from chain...");
  const { fetchAllOptionMetadata } = await import("./config/metadata");
  const optionsMap = await fetchAllOptionMetadata();

  // Resolve each option's collateral → spot-feed symbol (ETH, BTC, …).
  // Drives both which spot prices we poll and which underlying each option is
  // registered under, so puts/calls on different underlyings don't all collapse
  // into "ETH" pricing the way they used to.
  const chainId = getCurrentChainId();
  const underlyingByOption = new Map<string, string>();
  const feedSymbols = new Set<string>();
  for (const [address, metadata] of optionsMap.entries()) {
    // For calls, the collateral IS the underlying (e.g. WETH-collateralized call).
    // For puts, the collateral is the consideration (e.g. USDC-collateralized
    // put on WBTC) so the underlying is on the consideration side. Look up the
    // right side per-option.
    const refAddress = metadata.isPut ? metadata.considerationAddress : metadata.collateralAddress;
    const tok = getTokenByAddress(chainId, refAddress);
    const feed = feedSymbolFor(tok?.symbol);
    if (feed) {
      underlyingByOption.set(address, feed);
      feedSymbols.add(feed);
    } else {
      console.warn(
        `⚠️  Unknown ${metadata.isPut ? "consideration" : "collateral"} ${refAddress} (chainId ${chainId}) for option ${address}; skipping spot-price registration.`,
      );
    }
  }
  if (feedSymbols.size === 0) {
    console.warn("⚠️  No underlyings discovered — falling back to ETH spot polling.");
    feedSymbols.add("ETH");
  }
  const symbolList = Array.from(feedSymbols);
  console.log(`Underlyings discovered from on-chain options: ${symbolList.join(", ")}`);

  // Initial spot fetch with retries for each discovered underlying.
  for (const sym of symbolList) {
    let price: number | null = null;
    for (let attempt = 1; attempt <= 5; attempt++) {
      price = await spotFeed.getPrice(sym);
      if (price) break;
      console.warn(`⚠️  Spot ${sym} fetch attempt ${attempt}/5 failed, retrying in ${attempt * 2}s...`);
      await new Promise(r => setTimeout(r, attempt * 2000));
      spotFeed.clearCache();
    }
    if (price) {
      pricer.setSpotPrice(sym, price);
      console.log(`💲 Initial ${sym} spot price: $${price.toFixed(2)}`);
    } else {
      console.warn(`⚠️  Failed to fetch ${sym} spot after retries, pricing for ${sym} options may fail`);
    }
  }

  spotFeed.startPolling(symbolList, 30000);

  const { getPublicClient } = await import("./config/client");
  const client = getPublicClient();
  // ERC20 decimals() — options inherit the collateral token's decimals (6 for USDC-backed puts,
  // 18 for WETH-backed calls), so we must read it rather than assume 18.
  const DECIMALS_ABI = [
    { name: "decimals", type: "function", stateMutability: "view", inputs: [], outputs: [{ type: "uint8" }] },
  ] as const;

  const addresses = Array.from(optionsMap.keys());
  const decimalsByAddress = new Map<string, number>();
  const BATCH = 16;
  for (let i = 0; i < addresses.length; i += BATCH) {
    const batch = addresses.slice(i, i + BATCH);
    const results = await Promise.all(
      batch.map(addr =>
        client
          .readContract({ address: addr as `0x${string}`, abi: DECIMALS_ABI, functionName: "decimals" })
          .then(d => Number(d))
          .catch(() => 18),
      ),
    );
    batch.forEach((addr, k) => decimalsByAddress.set(addr, results[k]));
  }

  for (const [address, metadata] of optionsMap.entries()) {
    pricer.registerOption({
      optionAddress: address,
      underlying: underlyingByOption.get(address) ?? "ETH",
      strike: metadata.strike,
      expiry: metadata.expirationTimestamp,
      isPut: metadata.isPut,
      decimals: decimalsByAddress.get(address) ?? 18,
      collateralAddress: metadata.collateralAddress,
    });
  }
  console.log(`Registered ${optionsMap.size} options with pricer`);

  await startDirectMode(pricer);

  const shutdown = async () => {
    console.log("\nShutting down...");
    spotFeed.stop();
    process.exit(0);
  };
  process.on("SIGINT", shutdown);
  process.on("SIGTERM", shutdown);
}

main().catch(err => {
  console.error("Fatal error:", err);
  process.exit(1);
});
