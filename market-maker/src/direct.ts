#!/usr/bin/env node
import "dotenv/config";
import { Pricer } from "./pricing/pricer";
import { SpotFeed } from "./pricing/spotFeed";
import { startDirectMode } from "./modes/direct";

async function main() {
  console.log("Starting market-maker in DIRECT mode");

  // Initialize spot feed and pricer
  const spotFeed = new SpotFeed();
  const pricer = new Pricer({ spotFeed });
  spotFeed.start();

  // Start direct mode
  await startDirectMode(pricer);

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
