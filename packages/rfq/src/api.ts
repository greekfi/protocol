import express from "express";
import cors from "cors";
import { isOptionToken, getOption } from "./optionsList";

const app = express();
app.use(cors());
app.use(express.json());

interface QuoteRequest {
  buy_tokens: string;
  sell_tokens: string;
  sell_amounts: string;
  taker_address: string;
}

// Simple quote endpoint that mimics Bebop's API format
app.get("/quote", async (req, res) => {
  try {
    const { buy_tokens, sell_tokens, sell_amounts, taker_address } = req.query as any;

    if (!buy_tokens || !sell_tokens || !sell_amounts) {
      return res.status(400).json({ error: "Missing required parameters" });
    }

    // Check if either token is an option
    const isBuyTokenOption = isOptionToken(buy_tokens);
    const isSellTokenOption = isOptionToken(sell_tokens);

    if (!isBuyTokenOption && !isSellTokenOption) {
      return res.status(400).json({ error: "Neither token is an option token" });
    }

    const sellAmount = BigInt(sell_amounts);
    let buyAmount: bigint;
    let finalBuyToken = buy_tokens;
    let finalSellToken = sell_tokens;
    let finalSellAmount = sell_amounts;

    if (isBuyTokenOption) {
      // User buying options from us
      const optionInfo = getOption(buy_tokens);
      if (!optionInfo) {
        return res.status(400).json({ error: "Option not in price list" });
      }

      // Use ask price
      const askPriceUSDC = parseFloat(optionInfo.askPrice);
      const pricePerOption = BigInt(Math.floor(askPriceUSDC * 1e6));
      const sellAmountNeeded = (sellAmount * pricePerOption) / 1000000000000000000n;

      buyAmount = sellAmount;
      finalSellAmount = sellAmountNeeded.toString();

      console.log(`Quote request: Buy ${buyAmount.toString()} options for ${finalSellAmount} USDC (ask: $${optionInfo.askPrice})`);
    } else {
      // User selling options to us
      const optionInfo = getOption(sell_tokens);
      if (!optionInfo) {
        return res.status(400).json({ error: "Option not in price list" });
      }

      // Use bid price
      const bidPriceUSDC = parseFloat(optionInfo.bidPrice);
      const pricePerOption = BigInt(Math.floor(bidPriceUSDC * 1e6));
      buyAmount = (sellAmount * pricePerOption) / 1000000000000000000n;

      console.log(`Quote request: Sell ${sellAmount.toString()} options for ${buyAmount.toString()} USDC (bid: $${optionInfo.bidPrice})`);
    }

    // Return quote in Bebop format
    const quote = {
      buyAmount: buyAmount.toString(),
      sellAmount: finalSellAmount,
      price: (Number(buyAmount) / Number(sellAmount)).toString(),
      estimatedGas: "150000",
      tx: {
        to: "0x0000000000000000000000000000000000000000", // Placeholder
        data: "0x",
        value: "0",
        gas: "150000",
        gasPrice: "0",
      },
      routes: ["RFQ"],
    };

    res.json(quote);
  } catch (error: any) {
    console.error("Quote error:", error);
    res.status(500).json({ error: error.message });
  }
});

export function startAPIServer(port: number = 3001) {
  app.listen(port, () => {
    console.log(`RFQ API server listening on port ${port}`);
    console.log(`Quote endpoint: http://localhost:${port}/quote`);
  });
}
