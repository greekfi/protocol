import express from "express";
import cors from "cors";
import type { RFQManager } from "./RFQManager";
import type { MarketMakerManager } from "./MarketMakerManager";

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
