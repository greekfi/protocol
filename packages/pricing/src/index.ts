import dotenv from "dotenv";
dotenv.config();

import { createPricingRelay } from "./pricingRelay";
import { startPricingServer } from "./pricingServer";

// Configuration
const BEBOP_MARKETMAKER = process.env.BEBOP_MARKETMAKER;
const BEBOP_AUTHORIZATION = process.env.BEBOP_AUTHORIZATION;
const BEBOP_CHAINS = process.env.BEBOP_CHAINS?.split(",").map((s) => s.trim()) || ["ethereum"];
const PRICING_WS_PORT = parseInt(process.env.PRICING_WS_PORT || "3004");

if (!BEBOP_MARKETMAKER) {
  throw new Error("BEBOP_MARKETMAKER environment variable required");
}

if (!BEBOP_AUTHORIZATION) {
  throw new Error("BEBOP_AUTHORIZATION environment variable required");
}

console.log("🚀 Starting Bebop Pricing Relay Server");
console.log(`   Chains: ${BEBOP_CHAINS.join(", ")}`);
console.log(`   WebSocket port: ${PRICING_WS_PORT}`);

const pricingRelay = createPricingRelay({
  chains: BEBOP_CHAINS,
  name: BEBOP_MARKETMAKER,
  authorization: BEBOP_AUTHORIZATION,
});

// Log connection events
pricingRelay.on("connected", ({ chain }) => {
  console.log(`✅ Connected to ${chain} pricing feed`);
});

pricingRelay.on("disconnected", ({ chain }) => {
  console.log(`❌ Disconnected from ${chain} pricing feed`);
});

// Log price updates (limited to avoid spam)
let priceCount = 0;
pricingRelay.on("price", (event) => {
  priceCount++;
  if (priceCount % 100 === 1) {
    console.log(`💰 Received ${priceCount} prices. Latest: ${event.chain} ${event.pair.slice(0, 20)}...`);
  }
});

// Start the relay and server
pricingRelay.start();
const server = startPricingServer(pricingRelay, PRICING_WS_PORT);

// Graceful shutdown
function shutdown() {
  console.log("\n🛑 Shutting down...");
  server.stop();
  pricingRelay.stop();
  process.exit(0);
}

process.on("SIGINT", shutdown);
process.on("SIGTERM", shutdown);
