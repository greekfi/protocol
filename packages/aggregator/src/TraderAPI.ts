import express from "express";
import cors from "cors";
import type { RFQManager } from "./RFQManager";
import type { MarketMakerManager } from "./MarketMakerManager";
import type { BatchPricingRequest, BatchPricingResponse, BidirectionalPrice } from "./types";

export class TraderAPI {
  private app = express();
  private rfqManager: RFQManager;
  private makerManager: MarketMakerManager;

  constructor(rfqManager: RFQManager, makerManager: MarketMakerManager) {
    this.rfqManager = rfqManager;
    this.makerManager = makerManager;

    this.app.use(cors());
    this.app.use(express.json());

    this.setupRoutes();
  }

  private setupRoutes(): void {
    // Health check
    this.app.get("/health", (req, res) => {
      res.json({
        status: "ok",
        connected_makers: this.makerManager.getConnectedMakers().length,
        pending_rfqs: this.rfqManager.getPendingCount(),
      });
    });

    // Get quote
    this.app.get("/quote", async (req, res) => {
      try {
        const { buy_tokens, sell_tokens, sell_amounts, taker_address } = req.query as any;

        if (!buy_tokens || !sell_tokens || !sell_amounts || !taker_address) {
          return res.status(400).json({
            error: "Missing required parameters: buy_tokens, sell_tokens, sell_amounts, taker_address",
          });
        }

        console.log(`\n📞 Quote request from ${taker_address}`);
        console.log(`   Buy: ${buy_tokens}`);
        console.log(`   Sell: ${sell_amounts} of ${sell_tokens}`);

        // Create RFQ
        const quotePromise = this.rfqManager.createRFQ({
          buy_tokens: [{ token: buy_tokens, amount: sell_amounts }],
          sell_tokens: [{ token: sell_tokens, amount: sell_amounts }],
          taker_address,
        });

        // Get the RFQ ID to broadcast
        const rfqs = Array.from((this.rfqManager as any).pendingRFQs.keys());
        const rfqId = rfqs[rfqs.length - 1];

        const rfqMessage = this.rfqManager.getRFQMessage(rfqId);
        if (rfqMessage) {
          // Broadcast to market makers
          const sentCount = this.makerManager.broadcastRFQ(rfqMessage);

          if (sentCount === 0) {
            return res.status(404).json({
              error: "No market makers available for these tokens",
            });
          }
        }

        // Wait for quotes (with timeout)
        const bestQuote = await quotePromise;

        if (!bestQuote) {
          return res.status(404).json({
            error: "No quotes received from market makers",
          });
        }

        console.log(`✅ Returning best quote to trader`);
        res.json(bestQuote);
      } catch (error: any) {
        console.error("Quote error:", error);
        res.status(500).json({ error: error.message });
      }
    });

    // Get connected market makers
    this.app.get("/makers", (req, res) => {
      const makers = this.makerManager.getConnectedMakers().map((m) => ({
        id: m.id,
        name: m.name,
        supported_tokens: m.supportedTokens.length,
        is_alive: m.isAlive,
      }));

      res.json({ makers, count: makers.length });
    });

    // Batch pricing endpoint - get bidirectional prices for multiple token pairs
    this.app.post("/batch-prices", async (req, res) => {
      try {
        const { pairs, taker_address } = req.body as BatchPricingRequest;

        if (!pairs || !Array.isArray(pairs) || pairs.length === 0) {
          return res.status(400).json({
            error: "Missing or invalid 'pairs' array in request body",
          });
        }

        console.log(`\n📊 Batch pricing request for ${pairs.length} pairs`);

        const results: BidirectionalPrice[] = [];
        const takerAddr = taker_address || "0x0000000000000000000000000000000000000001";

        // Process each pair in parallel
        const pricePromises = pairs.map(async (pair) => {
          const { tokenA, tokenB } = pair;

          console.log(`   Processing pair: ${tokenA.slice(0, 10)}... <-> ${tokenB.slice(0, 10)}...`);

          // Query both directions
          const [sellAResult, sellBResult] = await Promise.allSettled([
            this.getQuoteForDirection(tokenA, tokenB, takerAddr),
            this.getQuoteForDirection(tokenB, tokenA, takerAddr),
          ]);

          const bidirectionalPrice: BidirectionalPrice = {
            tokenA,
            tokenB,
            sellA: {
              price: null,
              maxInput: null,
              maxOutput: null,
            },
            sellB: {
              price: null,
              maxInput: null,
              maxOutput: null,
            },
          };

          // Process A -> B direction
          if (sellAResult.status === "fulfilled" && sellAResult.value) {
            const quote = sellAResult.value;
            bidirectionalPrice.sellA = {
              price: quote.price,
              maxInput: quote.sellAmount,
              maxOutput: quote.buyAmount,
            };
          }

          // Process B -> A direction
          if (sellBResult.status === "fulfilled" && sellBResult.value) {
            const quote = sellBResult.value;
            bidirectionalPrice.sellB = {
              price: quote.price,
              maxInput: quote.sellAmount,
              maxOutput: quote.buyAmount,
            };
          }

          return bidirectionalPrice;
        });

        const settledResults = await Promise.all(pricePromises);
        results.push(...settledResults);

        const response: BatchPricingResponse = {
          pairs: results,
          timestamp: Date.now(),
        };

        console.log(`✅ Returning batch prices for ${results.length} pairs`);
        res.json(response);
      } catch (error: any) {
        console.error("Batch pricing error:", error);
        res.status(500).json({ error: error.message });
      }
    });

    // GET version for simpler testing
    this.app.get("/batch-prices", async (req, res) => {
      try {
        const pairsParam = req.query.pairs as string;
        const taker_address = req.query.taker_address as string;

        if (!pairsParam) {
          return res.status(400).json({
            error: "Missing 'pairs' query parameter. Format: tokenA1,tokenB1;tokenA2,tokenB2",
            example: "/batch-prices?pairs=0xToken1,0xToken2;0xToken3,0xToken4",
          });
        }

        // Parse pairs from query string (format: tokenA1,tokenB1;tokenA2,tokenB2)
        const pairs = pairsParam.split(";").map((pairStr) => {
          const [tokenA, tokenB] = pairStr.split(",");
          return { tokenA, tokenB };
        });

        // Reuse POST handler logic
        req.body = { pairs, taker_address };
        return this.app._router.handle(
          { ...req, method: "POST", url: "/batch-prices" },
          res,
          () => {}
        );
      } catch (error: any) {
        console.error("Batch pricing error:", error);
        res.status(500).json({ error: error.message });
      }
    });
  }

  // Helper to get quote for a specific direction
  private async getQuoteForDirection(
    sellToken: string,
    buyToken: string,
    takerAddress: string
  ): Promise<{ price: string; buyAmount: string; sellAmount: string } | null> {
    try {
      // Use a standard amount for price discovery (1 token worth)
      const testAmount = "1000000"; // Small test amount

      const quotePromise = this.rfqManager.createRFQ({
        buy_tokens: [{ token: buyToken, amount: testAmount }],
        sell_tokens: [{ token: sellToken, amount: testAmount }],
        taker_address: takerAddress,
      });

      const rfqs = Array.from((this.rfqManager as any).pendingRFQs.keys()) as string[];
      const rfqId = rfqs[rfqs.length - 1];

      const rfqMessage = this.rfqManager.getRFQMessage(rfqId as string);
      if (rfqMessage) {
        const sentCount = this.makerManager.broadcastRFQ(rfqMessage);
        if (sentCount === 0) {
          return null;
        }
      }

      const bestQuote = await quotePromise;

      if (!bestQuote) {
        return null;
      }

      return {
        price: bestQuote.price,
        buyAmount: bestQuote.buyAmount,
        sellAmount: bestQuote.sellAmount,
      };
    } catch (error) {
      console.error(`Error getting quote for ${sellToken} -> ${buyToken}:`, error);
      return null;
    }
  }

  public start(port: number): void {
    this.app.listen(port, () => {
      console.log(`🌐 Trader API listening on http://localhost:${port}`);
      console.log(`   Quote endpoint: http://localhost:${port}/quote`);
      console.log(`   Health check: http://localhost:${port}/health`);
      console.log(`   Market makers: http://localhost:${port}/makers`);
    });
  }
}
