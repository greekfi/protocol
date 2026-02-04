import dotenv from "dotenv";
dotenv.config();
import WebSocket from "ws";
import { bebop } from "./pricing_pb";
import { BebopClient } from "./client";
import type { Chain, RFQRequest } from "./types";
import { isOptionToken, getOption, OPTION_ADDRESSES } from "./optionsList";
import { startAPIServer } from "./api";
import { getUSDCAddress } from "./constants";
import { calculateBidAsk } from "./blackScholes";
import { fetchSpotPrice, getSpotPrice, fetchAllOptionMetadata, getOptionMetadata } from "./optionMetadata";

// Configuration
const CHAIN_ID = process.env.CHAIN_ID ? parseInt(process.env.CHAIN_ID) : 1; // Default to Ethereum mainnet
const CHAIN = (process.env.CHAIN || "ethereum") as Chain; // For Bebop API compatibility
const MARKETMAKER = process.env.BEBOP_MARKETMAKER;
const AUTHORIZATION = process.env.BEBOP_AUTHORIZATION;
const MAKER_ADDRESS = process.env.MAKER_ADDRESS;
const PRIVATE_KEY = process.env.PRIVATE_KEY;

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

// Get option bid/ask prices using Black-Scholes
function getOptionPrices(optionAddress: string): { bid: number; ask: number } {
  // Use real on-chain metadata instead of hardcoded fake data
  const metadata = getOptionMetadata(optionAddress);
  if (!metadata) return { bid: 0, ask: 0 };

  const spot = getSpotPrice();

  const { bid, ask } = calculateBidAsk(
    spot,
    metadata.strike,
    metadata.expirationTimestamp,
    metadata.isPut,
    1.0,  // 100% volatility
    0.05, // 5% risk-free rate
    0.02  // 2% spread
  );

  return { bid, ask };
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
  // Send pricing updates every 10 seconds
  pricingInterval = setInterval(() => {
    sendPricingUpdate();
  }, 10000);

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

    // Add levels for options with valid metadata
    for (const addr of OPTION_ADDRESSES) {
      const metadata = getOptionMetadata(addr);
      if (!metadata) continue; // Skip options without metadata

      const option = getOption(addr); // For decimals
      const levelInfo = new LevelInfo();

      levelInfo.baseAddress = hexToBytes(addr);
      levelInfo.baseDecimals = option?.decimals ?? 6;
      levelInfo.quoteAddress = hexToBytes(USDC_ADDRESS);
      levelInfo.quoteDecimals = option?.quoteDecimals ?? 6;

      const { bid: bidPrice, ask: askPrice } = getOptionPrices(addr);

      const type = metadata.isPut ? "PUT (for 1 WETH)" : "CALL (for 1 WETH)";
      console.log(`   📊 ${addr.slice(0,10)}... $${metadata.strike.toFixed(0)} ${type} bid=${bidPrice.toFixed(2)} ask=${askPrice.toFixed(2)}`);

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

    pricingWs.send(buffer);
  } catch (error) {
    console.error("❌ Failed to encode Protobuf message:", error);
    console.error("   Stack:", (error as Error).stack);
  }
}

const client = new BebopClient({
  chain: CHAIN,
  chainId: CHAIN_ID,
  marketmaker: MARKETMAKER,
  authorization: AUTHORIZATION,
  makerAddress: MAKER_ADDRESS,
  privateKey: PRIVATE_KEY,
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

    let buyAmount: bigint;

    if (isBuyTokenOption) {
      // User buying options from us
      const optionInfo = getOption(buyToken.token);
      console.log("\n=== USER BUYING OPTIONS ===");
      console.log("Option info:", optionInfo);

      // When user buys options, they specify maker_amount (option tokens they want)
      const optionAmountWanted = BigInt(buyToken.amount);
      console.log("User wants to buy:", optionAmountWanted.toString(), "option tokens");

      if (!optionInfo) {
        return {
          type: "decline" as const,
          rfq_id: rfq.rfq_id,
          reason: "Option not in price list",
        };
      }

      // Use Black-Scholes ask price
      const { ask: askPriceUSDC } = getOptionPrices(buyToken.token);
      console.log("Ask price (USDC):", askPriceUSDC.toFixed(2));

      // Convert: askPrice (dollars) * 1e6 (USDC decimals) per 1e6 option tokens
      const pricePerOption = BigInt(Math.floor(askPriceUSDC * 1e6));
      console.log("Price per option (USDC wei):", pricePerOption.toString());

      // Calculate USDC needed based on option decimals (6 decimals)
      const usdcNeeded = (optionAmountWanted * pricePerOption) / BigInt(10 ** optionInfo.decimals);
      console.log("USDC needed:", usdcNeeded.toString());

      buyAmount = optionAmountWanted;
      console.log("Option tokens to give:", buyAmount.toString());

      console.log("\nFINAL QUOTE:");
      console.log("  User pays:", usdcNeeded.toString(), "USDC");
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
            amount: usdcNeeded.toString(),
          },
        ],
        expiry: Math.floor(Date.now() / 1000) + 30,
        _originalRequest: {
          ...rfq._originalRequest,
          taker_address: rfq.taker_address,
          receiver: rfq.receiver_address,
        },
      };

      console.log("\n📤 SENDING QUOTE TO BEBOP:");
      console.log(JSON.stringify(quoteResponse, null, 2));

      return quoteResponse;
    } else {
      // User selling options to us
      const optionInfo = getOption(sellToken.token);
      console.log("\n=== USER SELLING OPTIONS ===");
      console.log("Option info:", optionInfo);

      // When user sells options, they specify taker_amount (option tokens they're selling)
      const optionAmountSelling = BigInt(sellToken.amount);
      console.log("User wants to sell:", optionAmountSelling.toString(), "option tokens");

      if (!optionInfo) {
        return {
          type: "decline" as const,
          rfq_id: rfq.rfq_id,
          reason: "Option not in price list",
        };
      }

      // Use Black-Scholes bid price
      const { bid: bidPriceUSDC } = getOptionPrices(sellToken.token);
      console.log("Bid price (USDC):", bidPriceUSDC.toFixed(2));

      // Convert: bidPrice (dollars) * 1e6 (USDC decimals) per 1e6 option tokens
      const pricePerOption = BigInt(Math.floor(bidPriceUSDC * 1e6));
      console.log("Price per option (USDC wei):", pricePerOption.toString());

      // Calculate USDC to give based on option decimals (6 decimals)
      buyAmount = (optionAmountSelling * pricePerOption) / BigInt(10 ** optionInfo.decimals);
      console.log("USDC to give:", buyAmount.toString());

      console.log("\nFINAL QUOTE:");
      console.log("  User gives:", optionAmountSelling.toString(), "option tokens");
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
        _originalRequest: {
          ...rfq._originalRequest,
          taker_address: rfq.taker_address,
          receiver: rfq.receiver_address,
        },
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

// Initialize and start
async function initialize() {
  console.log(`Loaded ${OPTION_ADDRESSES.length} option contracts from static list`);

  // Fetch spot price first
  console.log("Fetching spot price...");
  await fetchSpotPrice();
  console.log(`Spot price: $${getSpotPrice()}`);

  // Fetch real on-chain metadata for all options
  console.log("Fetching on-chain option metadata...");
  await fetchAllOptionMetadata();
  console.log("Metadata fetched for all options");

  // Log options with Black-Scholes prices using real metadata
  console.log("\nOption prices (Black-Scholes, 100% vol):");
  let loggedCount = 0;
  for (const addr of OPTION_ADDRESSES) {
    const metadata = getOptionMetadata(addr);
    if (!metadata) continue;

    const { bid, ask } = getOptionPrices(addr);
    const type = metadata.isPut ? "PUT (for 1 WETH)" : "CALL (for 1 WETH)";
    console.log(`  - ${addr.slice(0, 10)}... Strike: $${metadata.strike.toFixed(2)} ${type} bid: $${bid.toFixed(2)}, ask: $${ask.toFixed(2)}`);

    loggedCount++;
    if (loggedCount >= 10) break;
  }
  const totalWithMetadata = OPTION_ADDRESSES.filter(a => getOptionMetadata(a)).length;
  if (totalWithMetadata > 10) {
    console.log(`  ... and ${totalWithMetadata - 10} more options with metadata`);
  }

  // Refresh spot price every 60 seconds
  setInterval(async () => {
    await fetchSpotPrice();
  }, 60000);

  // Start HTTP API server for direct quotes
  startAPIServer(3001);

  // Start RFQ client
  console.log(`\nStarting Bebop RFQ client on ${CHAIN}...`);
  client.connect().catch((error) => {
    console.error("Failed to connect:", error);
    process.exit(1);
  });

  // Start pricing WebSocket connection
  console.log(`Starting Bebop Pricing client on ${CHAIN}...`);
  connectPricingWebSocket();
}

initialize().catch((error) => {
  console.error("Initialization failed:", error);
  process.exit(1);
});
