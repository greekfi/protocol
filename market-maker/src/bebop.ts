#!/usr/bin/env node
import "dotenv/config";
import { Pricer } from "./pricing/pricer";
import { SpotFeed } from "./pricing/spotFeed";
import { startBebopMode } from "./modes/bebop";

async function main() {
  console.log("Starting market-maker in BEBOP mode");

  // Initialize spot feed and pricer
  const spotFeed = new SpotFeed();
  const pricer = new Pricer({
    spotFeed,
    defaultIV: parseFloat(process.env.DEFAULT_IV || "0.8"),
    riskFreeRate: parseFloat(process.env.RISK_FREE_RATE || "0.05"),
  });
  spotFeed.start();

  // Connect spot feed updates to pricer
  spotFeed.onPriceUpdate((symbol, price) => {
    pricer.setSpotPrice(symbol, price);
    console.log(`💲 Spot price updated: ${symbol} = $${price.toFixed(2)}`);
  });

  // Fetch initial spot price for ETH
  console.log("Fetching initial spot prices...");
  const ethPrice = await spotFeed.getPrice("ETH");
  if (ethPrice) {
    pricer.setSpotPrice("ETH", ethPrice);
    console.log(`💲 Initial ETH spot price: $${ethPrice.toFixed(2)}`);
  } else {
    console.warn("⚠️  Failed to fetch ETH spot price, pricing may fail");
  }

  // Load option metadata from chain and register with pricer
  console.log("Loading option metadata from chain...");
  const { fetchAllOptionMetadata } = await import("./config/metadata");
  const optionsMap = await fetchAllOptionMetadata();

  // Register each option with the pricer
  for (const [address, metadata] of optionsMap.entries()) {
    pricer.registerOption({
      optionAddress: address,
      underlying: "ETH", // All options are ETH options for now
      strike: metadata.strike,
      expiry: metadata.expirationTimestamp,
      isPut: metadata.isPut,
      decimals: 18, // Option tokens have 18 decimals
    });
  }

  console.log(`Registered ${optionsMap.size} options with pricer`);

  // Start bebop mode
  await startBebopMode(pricer);

  // Graceful shutdown
  const shutdown = async () => {
    console.log("\nShutting down...");
    spotFeed.stop();
    process.exit(0);
  };
  process.on("SIGINT", shutdown);
  process.on("SIGTERM", shutdown);
}

main().catch((err) => {
  console.error("Fatal error:", err);
  process.exit(1);
});
