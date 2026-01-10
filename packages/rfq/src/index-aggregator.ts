import dotenv from "dotenv";
dotenv.config();
import { AggregatorClient } from "./aggregatorClient";
import type { RFQRequest } from "./types";
import { isOptionToken, getOption } from "./optionsList";

const AGGREGATOR_WS = process.env.AGGREGATOR_WS || "ws://localhost:3003";
const MAKER_ID = process.env.MAKER_ID || "maker-001";
const MAKER_NAME = process.env.MAKER_NAME || "Option Market Maker";
const MAKER_ADDRESS = process.env.MAKER_ADDRESS;

if (!MAKER_ADDRESS) {
  throw new Error("MAKER_ADDRESS environment variable required");
}

const client = new AggregatorClient({
  wsUrl: AGGREGATOR_WS,
  makerId: MAKER_ID,
  makerName: MAKER_NAME,
  makerAddress: MAKER_ADDRESS,
});

// Handle incoming RFQ requests
client.onRFQ(async (rfq: RFQRequest) => {
  console.log("Received RFQ:", JSON.stringify(rfq, null, 2));

  try {
    const buyToken = rfq.buy_tokens[0];
    const sellToken = rfq.sell_tokens[0];

    if (!buyToken || !sellToken) {
      return null;
    }

    // Check if either token is one of our option contracts
    const isBuyTokenOption = isOptionToken(buyToken.token);
    const isSellTokenOption = isOptionToken(sellToken.token);

    if (!isBuyTokenOption && !isSellTokenOption) {
      console.log("Neither token is an option token, declining");
      return null;
    }

    const sellAmount = BigInt(sellToken.amount);
    let buyAmount: bigint;

    if (isBuyTokenOption) {
      // User buying options from us
      const optionInfo = getOption(buyToken.token);
      console.log("\n=== USER BUYING OPTIONS ===");
      console.log("Option info:", optionInfo);

      if (!optionInfo) {
        return null;
      }

      // Use ask price from the static list
      const askPriceUSDC = parseFloat(optionInfo.askPrice);
      const pricePerOption = BigInt(Math.floor(askPriceUSDC * 1e6));
      const sellAmountNeeded = (sellAmount * pricePerOption) / 1000000000000000000n;

      buyAmount = sellAmount;

      return {
        type: "quote",
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
        gas_estimate: "150000",
      };
    } else {
      // User selling options to us
      const optionInfo = getOption(sellToken.token);
      console.log("\n=== USER SELLING OPTIONS ===");
      console.log("Option info:", optionInfo);

      if (!optionInfo) {
        return null;
      }

      // Use bid price from the static list
      const bidPriceUSDC = parseFloat(optionInfo.bidPrice);
      const pricePerOption = BigInt(Math.floor(bidPriceUSDC * 1e6));
      buyAmount = (sellAmount * pricePerOption) / 1000000000000000000n;

      return {
        type: "quote",
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
        gas_estimate: "150000",
      };
    }
  } catch (error) {
    console.error("Error creating quote:", error);
    return null;
  }
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
console.log(`Starting RFQ client for aggregator...`);
console.log(`Connecting to: ${AGGREGATOR_WS}`);
client.connect().catch((error) => {
  console.error("Failed to connect:", error);
  process.exit(1);
});
