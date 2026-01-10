import dotenv from "dotenv";
dotenv.config();

import { MarketMakerManager } from "./MarketMakerManager";
import { RFQManager } from "./RFQManager";
import { TraderAPI } from "./TraderAPI";

const HTTP_PORT = parseInt(process.env.PORT || "3002");
const WS_PORT = parseInt(process.env.WS_PORT || "3003");

console.log(`
╔═══════════════════════════════════════════════════════════╗
║                                                           ║
║         🎯  RFQ AGGREGATOR SERVICE                        ║
║                                                           ║
║  Routing quotes between Market Makers and Traders        ║
║                                                           ║
╚═══════════════════════════════════════════════════════════╝
`);

// Initialize components
const rfqManager = new RFQManager();
const makerManager = new MarketMakerManager(WS_PORT);
const traderAPI = new TraderAPI(rfqManager, makerManager);

// Wire up event handlers
makerManager.onQuote = (quote) => {
  rfqManager.addQuote(quote);
};

makerManager.onDecline = (decline) => {
  rfqManager.addDecline(decline);
};

// Start trader API
traderAPI.start(HTTP_PORT);

console.log(`
📡 Market Makers connect to: ws://localhost:${WS_PORT}
🌐 Traders request quotes at: http://localhost:${HTTP_PORT}/quote

Waiting for market makers to connect...
`);

// Graceful shutdown
process.on("SIGINT", () => {
  console.log("\n\n🛑 Shutting down...");
  makerManager.shutdown();
  process.exit(0);
});

process.on("SIGTERM", () => {
  console.log("\n\n🛑 Shutting down...");
  makerManager.shutdown();
  process.exit(0);
});
