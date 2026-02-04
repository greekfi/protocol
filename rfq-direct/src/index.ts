import dotenv from "dotenv";
dotenv.config();

import { Pricer } from "./pricer";
import { createDefaultSpotFeed } from "./spotFeed";
import { QuoteServer } from "./quoteServer";
import { PricingStream } from "./pricingStream";
import type { OptionParams } from "./types";

// Configuration
const HTTP_PORT = parseInt(process.env.HTTP_PORT || "3010");
const WS_PORT = parseInt(process.env.WS_PORT || "3011");
const CHAIN_ID = parseInt(process.env.CHAIN_ID || "1");
const MAKER_ADDRESS = process.env.MAKER_ADDRESS || "0x0000000000000000000000000000000000000000";

// Price update configuration
const SPOT_POLL_INTERVAL = parseInt(process.env.SPOT_POLL_INTERVAL || "10000");
const PRICE_BROADCAST_INTERVAL = parseInt(process.env.PRICE_BROADCAST_INTERVAL || "5000");

// Pricing parameters
const DEFAULT_IV = parseFloat(process.env.DEFAULT_IV || "0.80");
const RISK_FREE_RATE = parseFloat(process.env.RISK_FREE_RATE || "0.05");
const BID_SPREAD = parseFloat(process.env.BID_SPREAD || "0.02");
const ASK_SPREAD = parseFloat(process.env.ASK_SPREAD || "0.02");

console.log(`
╔═══════════════════════════════════════════════════════════╗
║                                                           ║
║         📊  RFQ-DIRECT SERVICE                            ║
║                                                           ║
║  Standalone RFQ server with Black-Scholes pricing         ║
║                                                           ║
╚═══════════════════════════════════════════════════════════╝
`);

// Create pricer
const pricer = new Pricer({
  riskFreeRate: RISK_FREE_RATE,
  defaultIV: DEFAULT_IV,
  spreadConfig: {
    bidSpread: BID_SPREAD,
    askSpread: ASK_SPREAD,
    minSpread: 0.01,
  },
});

// Create spot feed and wire it to pricer
const spotFeed = createDefaultSpotFeed();
spotFeed.onPriceUpdate((symbol, price) => {
  pricer.setSpotPrice(symbol, price);
});

// Load options from environment or config
function loadOptions(): OptionParams[] {
  if (process.env.OPTIONS_CONFIG) {
    try {
      return JSON.parse(process.env.OPTIONS_CONFIG);
    } catch (error) {
      console.error("Failed to parse OPTIONS_CONFIG:", error);
    }
  }

  // Default options - configure based on your deployed contracts
  const defaultOptions: OptionParams[] = [
    {
      optionAddress: "0xa59feE2E6e08bBC8c88CE993947B025C76c62322",
      strike: 3000,
      expiry: Math.floor(Date.now() / 1000) + 7 * 24 * 60 * 60,
      isPut: true,
      underlying: "ETH",
      collateralAddress: "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48",
      considerationAddress: "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48",
      decimals: 6,
    },
  ];

  return defaultOptions;
}

// Register options
const options = loadOptions();
pricer.registerOptions(options);
console.log(`Registered ${options.length} option contracts`);

// Get unique underlyings
const underlyings = [...new Set(options.map((o) => o.underlying))];
console.log(`Underlyings: ${underlyings.join(", ")}`);

// Start spot price polling
spotFeed.startPolling(underlyings, SPOT_POLL_INTERVAL);
console.log(`Spot price polling started (every ${SPOT_POLL_INTERVAL}ms)`);

// Create quote server
const quoteServer = new QuoteServer({
  port: HTTP_PORT,
  pricer,
  makerAddress: MAKER_ADDRESS,
  chainId: CHAIN_ID,
});

// Create pricing stream
const pricingStream = new PricingStream({
  port: WS_PORT,
  pricer,
  updateIntervalMs: PRICE_BROADCAST_INTERVAL,
});

// Start services
quoteServer.start();
pricingStream.startBroadcasting();

console.log(`
📡 Services running:
   HTTP Quote API: http://localhost:${HTTP_PORT}
   WebSocket Prices: ws://localhost:${WS_PORT}

   Chain ID: ${CHAIN_ID}
   Maker: ${MAKER_ADDRESS}

   Pricing Config:
   - Risk-free rate: ${(RISK_FREE_RATE * 100).toFixed(1)}%
   - Default IV: ${(DEFAULT_IV * 100).toFixed(0)}%
   - Bid spread: ${(BID_SPREAD * 100).toFixed(1)}%
   - Ask spread: ${(ASK_SPREAD * 100).toFixed(1)}%
`);

// Graceful shutdown
process.on("SIGINT", () => {
  console.log("\n\nShutting down...");
  pricingStream.shutdown();
  process.exit(0);
});

process.on("SIGTERM", () => {
  console.log("\n\nShutting down...");
  pricingStream.shutdown();
  process.exit(0);
});

// Export for programmatic use
export { pricer, quoteServer, pricingStream, spotFeed };
export { Pricer } from "./pricer";
export { QuoteServer } from "./quoteServer";
export { PricingStream } from "./pricingStream";
export * from "./types";
export * from "./blackScholes";
export * from "./spotFeed";
