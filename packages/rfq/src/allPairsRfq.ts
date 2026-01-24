import dotenv from "dotenv";
dotenv.config();
import WebSocket from "ws";
import { bebop } from "./pricing_pb";
import { BebopClient } from "./client";
import type { Chain, RFQRequest } from "./types";
import { OPTIONS_LIST, isOptionToken, getOption } from "./optionsList";
import { getUSDCAddress } from "./constants";

// Configuration
const CHAIN_ID = process.env.CHAIN_ID ? parseInt(process.env.CHAIN_ID) : 1;
const CHAIN = (process.env.CHAIN || "ethereum") as Chain;
const MARKETMAKER = process.env.BEBOP_MARKETMAKER;
const AUTHORIZATION = process.env.BEBOP_AUTHORIZATION;
const MAKER_ADDRESS = process.env.MAKER_ADDRESS;
const PRIVATE_KEY = process.env.PRIVATE_KEY;

// Bebop API URLs
const BEBOP_WS_BASE = "wss://api.bebop.xyz/pmm";
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

// Protobuf types from generated code
const { LevelsSchema, LevelMsg, LevelInfo } = bebop;

// Helper function to convert hex address to bytes
function hexToBytes(hex: string): Buffer {
  const cleanHex = hex.startsWith("0x") ? hex.slice(2) : hex;
  return Buffer.from(cleanHex, "hex");
}

// Generate all token pairs from OPTIONS_LIST
// Each option paired with USDC in both directions
export interface TokenPair {
  baseToken: string;      // Option token
  quoteToken: string;     // USDC
  baseDecimals: number;
  quoteDecimals: number;
  bidPrice: string;       // Price when selling base (getting quote)
  askPrice: string;       // Price when buying base (paying quote)
  maxBidAmount: string;   // Max amount of base token we'll buy
  maxAskAmount: string;   // Max amount of base token we'll sell
  type: "CALL" | "PUT";
}

export function getAllPairs(): TokenPair[] {
  return OPTIONS_LIST.map(option => ({
    baseToken: option.address,
    quoteToken: USDC_ADDRESS,
    baseDecimals: option.decimals,
    quoteDecimals: 6, // USDC always 6 decimals
    bidPrice: option.bidPrice,
    askPrice: option.askPrice,
    maxBidAmount: "10000", // Max we'll buy (in whole tokens)
    maxAskAmount: "10000", // Max we'll sell (in whole tokens)
    type: option.type,
  }));
}

// Pricing WebSocket connection
let pricingWs: WebSocket | null = null;
let pricingInterval: NodeJS.Timeout | null = null;

function connectPricingWebSocket() {
  console.log(`[AllPairs] Connecting to pricing WebSocket: ${BEBOP_PRICING_ENDPOINT}`);

  pricingWs = new WebSocket(BEBOP_PRICING_ENDPOINT, [], {
    headers: {
      marketmaker: MARKETMAKER!,
      authorization: AUTHORIZATION!,
    },
  });

  pricingWs.on("open", () => {
    console.log("[AllPairs] ✅ Connected to Bebop Pricing WebSocket");
    startPricingSending();
  });

  pricingWs.on("message", (data) => {
    try {
      const text = data.toString();
      if (text.includes("error")) {
        console.log("[AllPairs] ❌ Pricing error:", text);
      } else if (text.includes("success")) {
        console.log("[AllPairs] ✅ Pricing accepted");
      }
    } catch (error) {
      console.log("[AllPairs] 📨 Binary response received");
    }
  });

  pricingWs.on("close", (code, reason) => {
    console.log(`[AllPairs] ❌ Pricing WebSocket closed: ${code} - ${reason.toString()}`);
    stopPricingSending();

    // Reconnect after 5 seconds
    setTimeout(() => {
      console.log("[AllPairs] 🔄 Reconnecting pricing WebSocket...");
      connectPricingWebSocket();
    }, 5000);
  });

  pricingWs.on("error", (error) => {
    console.error("[AllPairs] ❌ Pricing WebSocket error:", error.message);
  });
}

function startPricingSending() {
  // Send pricing updates every 5 seconds
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
    console.log("[AllPairs] ⚠️  Pricing WebSocket not ready, skipping update");
    return;
  }

  try {
    const pairs = getAllPairs();

    // Build protobuf message
    const levelsSchema = new LevelsSchema();
    levelsSchema.chainId = CHAIN_ID;
    levelsSchema.msgTopic = "pricing";
    levelsSchema.msgType = "update";
    levelsSchema.msg = new LevelMsg();
    levelsSchema.msg.makerAddress = hexToBytes(MAKER_ADDRESS!);
    levelsSchema.msg.levels = [];

    // Add levels for all pairs
    for (const pair of pairs) {
      const levelInfo = new LevelInfo();

      levelInfo.baseAddress = hexToBytes(pair.baseToken);
      levelInfo.baseDecimals = pair.baseDecimals;
      levelInfo.quoteAddress = hexToBytes(pair.quoteToken);
      levelInfo.quoteDecimals = pair.quoteDecimals;

      const bidPrice = parseFloat(pair.bidPrice);
      const askPrice = parseFloat(pair.askPrice);
      const maxAmount = parseFloat(pair.maxBidAmount);

      // Bids: what we pay to buy the base token
      levelInfo.bids = [];
      levelInfo.bids.push(bidPrice);
      levelInfo.bids.push(maxAmount);

      // Asks: what we charge to sell the base token
      levelInfo.asks = [];
      levelInfo.asks.push(askPrice);
      levelInfo.asks.push(maxAmount);

      levelsSchema.msg.levels.push(levelInfo);
    }

    // Encode to bytes
    const buffer = LevelsSchema.encode(levelsSchema).finish();

    console.log(`[AllPairs] 📤 Sending pricing update (${buffer.length} bytes, ${pairs.length} pairs)`);

    pricingWs.send(buffer);
  } catch (error) {
    console.error("[AllPairs] ❌ Failed to encode Protobuf message:", error);
  }
}

// RFQ Client for handling quote requests
const client = new BebopClient({
  chain: CHAIN,
  chainId: CHAIN_ID,
  marketmaker: MARKETMAKER,
  authorization: AUTHORIZATION,
  makerAddress: MAKER_ADDRESS,
  privateKey: PRIVATE_KEY,
});

// Handle incoming RFQ requests - supports all pairs in both directions
client.onRFQ(async (rfq: RFQRequest) => {
  console.log("[AllPairs] Received RFQ:", JSON.stringify(rfq, null, 2));

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
      console.log("[AllPairs] Neither token is an option token, declining");
      return {
        type: "decline" as const,
        rfq_id: rfq.rfq_id,
        reason: "Not an option token",
      };
    }

    let buyAmount: bigint;

    if (isBuyTokenOption) {
      // User buying options from us (we sell, they pay USDC)
      const optionInfo = getOption(buyToken.token);
      console.log("\n[AllPairs] === USER BUYING OPTIONS ===");
      console.log("[AllPairs] Option:", optionInfo?.type, optionInfo?.address);

      const optionAmountWanted = BigInt(buyToken.amount);
      console.log("[AllPairs] User wants to buy:", optionAmountWanted.toString(), "option tokens");

      if (!optionInfo) {
        return {
          type: "decline" as const,
          rfq_id: rfq.rfq_id,
          reason: "Option not in price list",
        };
      }

      // Use ask price from the list
      const askPriceUSDC = parseFloat(optionInfo.askPrice);
      const pricePerOption = BigInt(Math.floor(askPriceUSDC * 1e6));
      const usdcNeeded = (optionAmountWanted * pricePerOption) / BigInt(10 ** optionInfo.decimals);

      console.log("[AllPairs] Ask price:", askPriceUSDC, "USDC");
      console.log("[AllPairs] USDC needed:", usdcNeeded.toString());

      buyAmount = optionAmountWanted;

      const quoteResponse = {
        type: "quote" as const,
        rfq_id: rfq.rfq_id,
        maker_address: MAKER_ADDRESS,
        buy_tokens: [{ token: buyToken.token, amount: buyAmount.toString() }],
        sell_tokens: [{ token: sellToken.token, amount: usdcNeeded.toString() }],
        expiry: Math.floor(Date.now() / 1000) + 30,
        _originalRequest: {
          ...rfq._originalRequest,
          taker_address: rfq.taker_address,
          receiver: rfq.receiver_address,
        },
      };

      console.log("[AllPairs] 📤 Quote:", JSON.stringify(quoteResponse, null, 2));
      return quoteResponse;
    } else {
      // User selling options to us (we buy, they get USDC)
      const optionInfo = getOption(sellToken.token);
      console.log("\n[AllPairs] === USER SELLING OPTIONS ===");
      console.log("[AllPairs] Option:", optionInfo?.type, optionInfo?.address);

      const optionAmountSelling = BigInt(sellToken.amount);
      console.log("[AllPairs] User wants to sell:", optionAmountSelling.toString(), "option tokens");

      if (!optionInfo) {
        return {
          type: "decline" as const,
          rfq_id: rfq.rfq_id,
          reason: "Option not in price list",
        };
      }

      // Use bid price from the list
      const bidPriceUSDC = parseFloat(optionInfo.bidPrice);
      const pricePerOption = BigInt(Math.floor(bidPriceUSDC * 1e6));
      buyAmount = (optionAmountSelling * pricePerOption) / BigInt(10 ** optionInfo.decimals);

      console.log("[AllPairs] Bid price:", bidPriceUSDC, "USDC");
      console.log("[AllPairs] USDC to give:", buyAmount.toString());

      const quoteResponse = {
        type: "quote" as const,
        rfq_id: rfq.rfq_id,
        maker_address: MAKER_ADDRESS,
        buy_tokens: [{ token: buyToken.token, amount: buyAmount.toString() }],
        sell_tokens: [{ token: sellToken.token, amount: sellToken.amount }],
        expiry: Math.floor(Date.now() / 1000) + 30,
        _originalRequest: {
          ...rfq._originalRequest,
          taker_address: rfq.taker_address,
          receiver: rfq.receiver_address,
        },
      };

      console.log("[AllPairs] 📤 Quote:", JSON.stringify(quoteResponse, null, 2));
      return quoteResponse;
    }
  } catch (error) {
    console.error("[AllPairs] Error creating quote:", error);
    return {
      type: "decline" as const,
      rfq_id: rfq.rfq_id,
      reason: "Pricing error",
    };
  }
});

// Handle order updates
client.onOrder((order) => {
  console.log("[AllPairs] Order update:", JSON.stringify(order, null, 2));
});

// Graceful shutdown
process.on("SIGINT", () => {
  console.log("\n[AllPairs] Shutting down...");
  stopPricingSending();
  if (pricingWs) {
    pricingWs.close(1000, "Client disconnect");
  }
  client.disconnect();
  process.exit(0);
});

process.on("SIGTERM", () => {
  console.log("\n[AllPairs] Shutting down...");
  stopPricingSending();
  if (pricingWs) {
    pricingWs.close(1000, "Client disconnect");
  }
  client.disconnect();
  process.exit(0);
});

// Export for use by aggregator
export { getAllPairs as getPairs };

// Start if run directly
if (require.main === module) {
  console.log(`[AllPairs] Starting All Pairs RFQ on ${CHAIN} (chainId: ${CHAIN_ID})`);
  console.log(`[AllPairs] Loaded ${OPTIONS_LIST.length} option contracts`);

  const pairs = getAllPairs();
  pairs.forEach(pair => {
    console.log(`  - ${pair.baseToken}: bid $${pair.bidPrice} / ask $${pair.askPrice}`);
  });

  // Start RFQ client
  client.connect().catch((error) => {
    console.error("[AllPairs] Failed to connect:", error);
    process.exit(1);
  });

  // Start pricing WebSocket
  connectPricingWebSocket();
}
