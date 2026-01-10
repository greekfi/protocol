import dotenv from "dotenv";
dotenv.config();
import { BebopClient } from "./client";
import type { Chain, RFQRequest } from "./types";
import { OPTIONS_LIST, isOptionToken, getOption } from "./optionsList";
import { startAPIServer } from "./api";

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
  client.disconnect();
  process.exit(0);
});

process.on("SIGTERM", () => {
  console.log("\nShutting down...");
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

// Start client
console.log(`Starting Bebop RFQ client on ${CHAIN}...`);
client.connect().catch((error) => {
  console.error("Failed to connect:", error);
  process.exit(1);
});
