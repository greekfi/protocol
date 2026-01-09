import dotenv from "dotenv";
dotenv.config();
import { BebopClient } from "./client";
import type { Chain, RFQRequest } from "./types";

const CHAIN = (process.env.CHAIN || "ethereum") as Chain;
const MARKETMAKER = process.env.BEBOP_MARKETMAKER;
const AUTHORIZATION = process.env.BEBOP_AUTHORIZATION;
const MAKER_ADDRESS = process.env.MAKER_ADDRESS;

if (!MARKETMAKER) {
  throw new Error("BEBOP_MARKETMAKER environment variable required");
}

if (!AUTHORIZATION) {
  throw new Error("BEBOP_AUTHORIZATION environment variable required");
}

if (!MAKER_ADDRESS) {
  throw new Error("MAKER_ADDRESS environment variable required");
}

const client = new BebopClient({
  chain: CHAIN,
  marketmaker: MARKETMAKER,
  authorization: AUTHORIZATION,
  makerAddress: MAKER_ADDRESS,
});

// Handle incoming RFQ requests
client.onRFQ(async (rfq: RFQRequest) => {
  console.log("Received RFQ:", JSON.stringify(rfq, null, 2));

  // TODO: Implement your pricing logic here
  // For now, decline all requests
  return {
    type: "decline" as const,
    rfq_id: rfq.rfq_id,
    reason: "Not implemented",
  };
});

// Handle order updates
client.onOrder((order) => {
  console.log("Order update:", JSON.stringify(order, null, 2));
});

// Graceful shutdown
process.on("SIGINT", () => {
  console.log("\nShutting down...");
  client.disconnect();
  process.exit(0);
});

process.on("SIGTERM", () => {
  console.log("\nShutting down...");
  client.disconnect();
  process.exit(0);
});

// Start client
console.log(`Starting Bebop RFQ client on ${CHAIN}...`);
client.connect().catch((error) => {
  console.error("Failed to connect:", error);
  process.exit(1);
});
