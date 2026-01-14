import dotenv from "dotenv";
dotenv.config();
import WebSocket from "ws";
import { bebop } from "./pricing_pb";
import { BebopClient } from "./client";
import type { Chain, RFQRequest } from "./types";
import { OPTIONS_LIST, isOptionToken, getOption } from "./optionsList";
import { startAPIServer } from "./api";
import { getUSDCAddress } from "./constants";

// Configuration
const CHAIN_ID = process.env.CHAIN_ID ? parseInt(process.env.CHAIN_ID) : 1; // Default to Ethereum mainnet
const CHAIN = (process.env.CHAIN || "ethereum") as Chain; // For Bebop API compatibility
const MARKETMAKER = process.env.BEBOP_MARKETMAKER;
const AUTHORIZATION = process.env.BEBOP_AUTHORIZATION;
const MAKER_ADDRESS = process.env.MAKER_ADDRESS;

// Bebop API URLs
const BEBOP_WS_BASE = "wss://api.bebop.xyz/pmm";
const BEBOP_RFQ_ENDPOINT = `${BEBOP_WS_BASE}/${CHAIN}/v3/maker/quote`;
const BEBOP_PRICING_ENDPOINT = `${BEBOP_WS_BASE}/${CHAIN}/v3/maker/pricing?format=protobuf`;

if (!MARKETMAKER) {
  throw new Error("BEBOP_MARKETMAKER environment variable required");
}

if (!AUTHORIZATION) {
  throw new Error("BEBOP_AUTHORIZATION environment variable required");
}

if (!MAKER_ADDRESS) {
  throw new Error("MAKER_ADDRESS environment variable required");
}

const USDC_ADDRESS = getUSDCAddress(CHAIN_ID);

// Get option ask price for pricing stream
function getOptionPrice(optionAddress: string): number {
  const option = getOption(optionAddress);
  if (!option) return 0;
  return parseFloat(option.askPrice);
}

// Protobuf types from generated code
const { LevelsSchema, LevelMsg, LevelInfo } = bebop;

// Helper function to convert hex address to bytes
function hexToBytes(hex: string): Buffer {
  const cleanHex = hex.startsWith("0x") ? hex.slice(2) : hex;
  return Buffer.from(cleanHex, "hex");
}

// Pricing WebSocket connection
let pricingWs: WebSocket | null = null;
let pricingInterval: NodeJS.Timeout | null = null;

function connectPricingWebSocket() {
  console.log(`Connecting to pricing WebSocket: ${BEBOP_PRICING_ENDPOINT}`);

  pricingWs = new WebSocket(BEBOP_PRICING_ENDPOINT, [], {
    headers: {
      marketmaker: MARKETMAKER!,
      authorization: AUTHORIZATION!,
    },
  });

  pricingWs.on("open", () => {
    console.log("✅ Connected to Bebop Pricing WebSocket");
    startPricingSending();
  });

  pricingWs.on("message", (data) => {
    try {
      // Try to parse as text first
      const text = data.toString();
      console.log("📨 Pricing response (text):", text);

      // Try to parse as JSON
      try {
        const json = JSON.parse(text);
        console.log("📨 Pricing response (JSON):", JSON.stringify(json, null, 2));
      } catch {}
    } catch (error) {
      console.log("📨 Pricing response (binary):", Array.from(data as Buffer).slice(0, 100));
    }
  });

  pricingWs.on("close", (code, reason) => {
    console.log(`❌ Pricing WebSocket closed: ${code} - ${reason.toString()}`);
    stopPricingSending();

    // Reconnect after 5 seconds
    setTimeout(() => {
      console.log("🔄 Reconnecting pricing WebSocket...");
      connectPricingWebSocket();
    }, 5000);
  });

  pricingWs.on("error", (error) => {
    console.error("❌ Pricing WebSocket error:", error.message);
  });
}

function startPricingSending() {
  // Send pricing updates every 5 seconds (well above the 0.4s minimum from Bebop)
  pricingInterval = setInterval(() => {
    sendPricingUpdate();
  }, 5000);

  // Send initial pricing update after a short delay
  setTimeout(() => {
    sendPricingUpdate();
  }, 1000);
}

function stopPricingSending() {
  if (pricingInterval) {
    clearInterval(pricingInterval);
    pricingInterval = null;
  }
}

function sendPricingUpdate() {
  if (!pricingWs || pricingWs.readyState !== WebSocket.OPEN) {
    console.log("⚠️  Pricing WebSocket not ready, skipping update");
    return;
  }

  try {
    // Build protobuf message like Python example (with camelCase properties)
    const levelsSchema = new LevelsSchema();
    levelsSchema.chainId = CHAIN_ID;
    levelsSchema.msgTopic = "pricing";
    levelsSchema.msgType = "update";
    levelsSchema.msg = new LevelMsg();
    levelsSchema.msg.makerAddress = hexToBytes(MAKER_ADDRESS!);
    levelsSchema.msg.levels = [];

    // Add levels for all options
    for (const option of OPTIONS_LIST) {
      const levelInfo = new LevelInfo();

      levelInfo.baseAddress = hexToBytes(option.address);
      levelInfo.baseDecimals = option.decimals;
      levelInfo.quoteAddress = hexToBytes(USDC_ADDRESS);
      levelInfo.quoteDecimals = option.quoteDecimals;

      const askPrice = getOptionPrice(option.address);
      const bidPrice = parseFloat(option.bidPrice);

      // Flatten bids/asks like Python: [price, amount, price, amount, ...]
      levelInfo.bids = [];
      levelInfo.bids.push(bidPrice);
      levelInfo.bids.push(1000.0);

      levelInfo.asks = [];
      levelInfo.asks.push(askPrice);
      levelInfo.asks.push(1000.0);

      levelsSchema.msg.levels.push(levelInfo);
    }

    // Encode to bytes
    const buffer = LevelsSchema.encode(levelsSchema).finish();

    console.log("📤 Sending Protobuf pricing update (", buffer.length, "bytes )");
    console.log(`   ${OPTIONS_LIST.length} levels, bids/asks: $${parseFloat(OPTIONS_LIST[0].bidPrice)}/$${parseFloat(OPTIONS_LIST[0].askPrice)}`);

    pricingWs.send(buffer);
  } catch (error) {
    console.error("❌ Failed to encode Protobuf message:", error);
    console.error("   Stack:", (error as Error).stack);
  }
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

  try {
    const buyToken = rfq.buy_tokens[0];
    const sellToken = rfq.sell_tokens[0];

    if (!buyToken || !sellToken) {
      return {
        type: "decline" as const,
        rfq_id: rfq.rfq_id,
        reason: "Invalid token amounts",
      };
    }

    // Check if either token is one of our option contracts
    const isBuyTokenOption = isOptionToken(buyToken.token);
    const isSellTokenOption = isOptionToken(sellToken.token);

    if (!isBuyTokenOption && !isSellTokenOption) {
      console.log("Neither token is an option token, declining");
      return {
        type: "decline" as const,
        rfq_id: rfq.rfq_id,
        reason: "Not an option token",
      };
    }

    const sellAmount = BigInt(sellToken.amount);
    let buyAmount: bigint;

    if (isBuyTokenOption) {
      // User buying options from us
      const optionInfo = getOption(buyToken.token);
      console.log("\n=== USER BUYING OPTIONS ===");
      console.log("Option info:", optionInfo);
      console.log("User wants to buy:", sellAmount.toString(), "option tokens");

      if (!optionInfo) {
        return {
          type: "decline" as const,
          rfq_id: rfq.rfq_id,
          reason: "Option not in price list",
        };
      }

      // Use ask price from the static list
      const askPriceUSDC = parseFloat(optionInfo.askPrice);
      console.log("Ask price (USDC):", askPriceUSDC);

      // Convert: askPrice (dollars) * 1e6 (USDC decimals) per 1e18 option tokens
      const pricePerOption = BigInt(Math.floor(askPriceUSDC * 1e6));
      console.log("Price per option (USDC wei):", pricePerOption.toString());

      const sellAmountNeeded = (sellAmount * pricePerOption) / 1000000000000000000n;
      console.log("USDC needed:", sellAmountNeeded.toString());

      buyAmount = sellAmount;
      console.log("Option tokens to give:", buyAmount.toString());

      console.log("\nFINAL QUOTE:");
      console.log("  User pays:", sellAmountNeeded.toString(), "USDC");
      console.log("  User gets:", buyAmount.toString(), "option tokens");

      const quoteResponse = {
        type: "quote" as const,
        rfq_id: rfq.rfq_id,
        maker_address: MAKER_ADDRESS,
        buy_tokens: [
          {
            token: buyToken.token,
            amount: buyAmount.toString(),
          },
        ],
        sell_tokens: [
          {
            token: sellToken.token,
            amount: sellAmountNeeded.toString(),
          },
        ],
        expiry: Math.floor(Date.now() / 1000) + 30,
      };

      console.log("\n📤 SENDING QUOTE TO BEBOP:");
      console.log(JSON.stringify(quoteResponse, null, 2));

      return quoteResponse;
    } else {
      // User selling options to us
      const optionInfo = getOption(sellToken.token);
      console.log("\n=== USER SELLING OPTIONS ===");
      console.log("Option info:", optionInfo);
      console.log("User wants to sell:", sellAmount.toString(), "option tokens");

      if (!optionInfo) {
        return {
          type: "decline" as const,
          rfq_id: rfq.rfq_id,
          reason: "Option not in price list",
        };
      }

      // Use bid price from the static list
      const bidPriceUSDC = parseFloat(optionInfo.bidPrice);
      console.log("Bid price (USDC):", bidPriceUSDC);

      // Convert: bidPrice (dollars) * 1e6 (USDC decimals) per 1e18 option tokens
      const pricePerOption = BigInt(Math.floor(bidPriceUSDC * 1e6));
      console.log("Price per option (USDC wei):", pricePerOption.toString());

      buyAmount = (sellAmount * pricePerOption) / 1000000000000000000n;
      console.log("USDC to give:", buyAmount.toString());

      console.log("\nFINAL QUOTE:");
      console.log("  User gives:", sellAmount.toString(), "option tokens");
      console.log("  User gets:", buyAmount.toString(), "USDC");

      const quoteResponse = {
        type: "quote" as const,
        rfq_id: rfq.rfq_id,
        maker_address: MAKER_ADDRESS,
        buy_tokens: [
          {
            token: buyToken.token,
            amount: buyAmount.toString(),
          },
        ],
        sell_tokens: [
          {
            token: sellToken.token,
            amount: sellToken.amount,
          },
        ],
        expiry: Math.floor(Date.now() / 1000) + 30,
      };

      console.log("\n📤 SENDING QUOTE TO BEBOP:");
      console.log(JSON.stringify(quoteResponse, null, 2));

      return quoteResponse;
    }
  } catch (error) {
    console.error("Error creating quote:", error);
    return {
      type: "decline" as const,
      rfq_id: rfq.rfq_id,
      reason: "Pricing error",
    };
  }
});

// Handle order updates
client.onOrder((order) => {
  console.log("Order update:", JSON.stringify(order, null, 2));
});

// Graceful shutdown
process.on("SIGINT", () => {
  console.log("\nShutting down...");
  stopPricingSending();
  if (pricingWs) {
    pricingWs.close(1000, "Client disconnect");
  }
  client.disconnect();
  process.exit(0);
});

process.on("SIGTERM", () => {
  console.log("\nShutting down...");
  stopPricingSending();
  if (pricingWs) {
    pricingWs.close(1000, "Client disconnect");
  }
  client.disconnect();
  process.exit(0);
});

// Load static options list
console.log(`Loaded ${OPTIONS_LIST.length} option contracts from static list`);
OPTIONS_LIST.forEach(opt => {
  console.log(`  - ${opt.address}: ${opt.type} (bid: $${opt.bidPrice}, ask: $${opt.askPrice})`);
});

// Start HTTP API server for direct quotes
startAPIServer(3001);

// Start RFQ client
console.log(`Starting Bebop RFQ client on ${CHAIN}...`);
client.connect().catch((error) => {
  console.error("Failed to connect:", error);
  process.exit(1);
});

// Start pricing WebSocket connection
console.log(`Starting Bebop Pricing client on ${CHAIN}...`);
connectPricingWebSocket();
