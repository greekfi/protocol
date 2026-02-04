#!/usr/bin/env node
import "dotenv/config";
import { Pricer } from "./pricing/pricer";
import { SpotFeed } from "./pricing/spotFeed";
import { startBebopMode } from "./modes/bebop";

async function main() {
  console.log("Starting market-maker in BEBOP mode");

  // Initialize spot feed and pricer
  const spotFeed = new SpotFeed();
  const pricer = new Pricer({ spotFeed });
  spotFeed.start();

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
