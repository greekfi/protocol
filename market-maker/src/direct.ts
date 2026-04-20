#!/usr/bin/env node
import "dotenv/config";
import { Pricer } from "./pricing/pricer";
import { SpotFeed } from "./pricing/spotFeed";
import { startDirectMode } from "./modes/direct";

async function main() {
  console.log("Starting market-maker in DIRECT mode");

  const spotFeed = new SpotFeed();
  const pricer = new Pricer({
    spotFeed,
    defaultIV: parseFloat(process.env.DEFAULT_IV || "0.8"),
    riskFreeRate: parseFloat(process.env.RISK_FREE_RATE || "0.05"),
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

  for (const [address, metadata] of optionsMap.entries()) {
    pricer.registerOption({
      optionAddress: address,
      underlying: "ETH",
      strike: metadata.strike,
      expiry: metadata.expirationTimestamp,
      isPut: metadata.isPut,
      decimals: 18,
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
