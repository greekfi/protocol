#!/usr/bin/env node
import "dotenv/config";
import { Pricer } from "./pricing/pricer";
import { SpotFeed } from "./pricing/spotFeed";
import { startDirectMode } from "./modes/direct";

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

  let ethPrice: number | null = null;
  for (let attempt = 1; attempt <= 5; attempt++) {
    ethPrice = await spotFeed.getPrice("ETH");
    if (ethPrice) break;
    console.warn(`⚠️  Spot price fetch attempt ${attempt}/5 failed, retrying in ${attempt * 2}s...`);
    await new Promise(r => setTimeout(r, attempt * 2000));
    spotFeed.clearCache();
  }
  if (ethPrice) {
    pricer.setSpotPrice("ETH", ethPrice);
    console.log(`💲 Initial ETH spot price: $${ethPrice.toFixed(2)}`);
  } else {
    console.warn("⚠️  Failed to fetch ETH spot price after retries, pricing may fail");
  }

  spotFeed.startPolling(["ETH"], 30000);

  console.log("Loading option metadata from chain...");
  const { fetchAllOptionMetadata } = await import("./config/metadata");
  const optionsMap = await fetchAllOptionMetadata();

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
      underlying: "ETH",
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
