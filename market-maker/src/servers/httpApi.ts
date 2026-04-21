import express, { type Request, type Response } from "express";
import cors from "cors";
import type { Pricer } from "../pricing/pricer";
import type { QuoteResponse, ErrorResponse } from "../pricing/types";
import { signQuote, type QuoteData } from "../bebop/signing";

/** Signs a QuoteData without exposing the underlying key. Produced at factory time. */
export type Signer = (data: QuoteData) => Promise<{ signature: string }>;

export interface QuoteServerConfig {
  port: number;
  pricer: Pricer;
  makerAddress: string;
  chainId: number;
  /** Optional signer closure. If absent, /quote responses omit signature fields. */
  signer?: Signer;
}

export class QuoteServer {
  private app = express();
  private pricer: Pricer;
  private makerAddress: string;
  private chainId: number;
  private signer?: Signer;

  constructor(private config: QuoteServerConfig) {
    this.pricer = config.pricer;
    this.makerAddress = config.makerAddress;
    this.chainId = config.chainId;
    this.signer = config.signer;

    this.app.use(cors());
    this.app.use(express.json());
    this.setupRoutes();
  }

  private setupRoutes(): void {
    // Health check
    this.app.get("/health", (req, res) => {
      const options = this.pricer.getAllOptions();
      res.json({
        status: "ok",
        chainId: this.chainId,
        optionsCount: options.length,
        makerAddress: this.makerAddress,
      });
    });

    // Get all available options with live prices
    this.app.get("/options", (req, res) => {
      const options = this.pricer.getAllOptions();
      const priced = options.map((opt) => {
        const price = this.pricer.price(opt.optionAddress);
        return {
          address: opt.optionAddress,
          underlying: opt.underlying,
          strike: opt.strike,
          expiry: opt.expiry,
          isPut: opt.isPut,
          decimals: opt.decimals,
          bid: price?.bid ?? null,
          ask: price?.ask ?? null,
          mid: price?.mid ?? null,
          delta: price?.delta ?? null,
          gamma: price?.gamma ?? null,
          theta: price?.theta ?? null,
          vega: price?.vega ?? null,
          iv: price?.iv ?? null,
          spotPrice: price?.spotPrice ?? null,
        };
      });
      res.json({ options: priced });
    });

    // Get quote - Bebop-compatible format
    this.app.get("/quote", async (req: Request, res: Response) => {
      try {
        const quote = await this.handleQuoteRequest(req.query as Record<string, string | undefined>);
        res.json(quote);
      } catch (error: unknown) {
        console.error("Quote error:", error);
        const errorResponse: ErrorResponse = {
          error: error instanceof Error ? error.message : "Quote generation failed",
          code: "QUOTE_ERROR",
        };
        res.status(400).json(errorResponse);
      }
    });

    // Get price for a specific option
    this.app.get("/price/:optionAddress", (req, res) => {
      const { optionAddress } = req.params;
      const price = this.pricer.price(optionAddress);

      if (!price) {
        res.status(404).json({ error: "Option not found or not priced" });
        return;
      }

      const option = this.pricer.getOption(optionAddress);
      res.json({
        optionAddress,
        underlying: option?.underlying,
        strike: option?.strike,
        expiry: option?.expiry,
        isPut: option?.isPut,
        ...price,
      });
    });
  }

  private async handleQuoteRequest(params: Record<string, string | undefined>): Promise<QuoteResponse> {
    const {
      buyToken,
      sellToken,
      buy_tokens,
      sell_tokens,
      sellAmount,
      buyAmount,
      sell_amounts,
      buy_amounts,
      takerAddress,
      taker_address,
    } = params;

    // Normalize parameters (support both formats)
    const normalizedBuyToken = buyToken || buy_tokens;
    const normalizedSellToken = sellToken || sell_tokens;
    const normalizedSellAmount = sellAmount || sell_amounts;
    const normalizedBuyAmount = buyAmount || buy_amounts;
    const normalizedTaker = takerAddress || taker_address || "0x0000000000000000000000000000000000000000";

    if (!normalizedBuyToken || !normalizedSellToken) {
      throw new Error("buyToken and sellToken are required");
    }

    if (!normalizedSellAmount && !normalizedBuyAmount) {
      throw new Error("Either sellAmount or buyAmount is required");
    }

    // Determine if user is buying or selling options
    const isBuyingOption = this.pricer.isOption(normalizedBuyToken);
    const isSellingOption = this.pricer.isOption(normalizedSellToken);

    if (!isBuyingOption && !isSellingOption) {
      throw new Error("Neither token is a registered option");
    }

    let buyAmountBigInt: bigint;
    let sellAmountBigInt: bigint;
    let optionAddress: string;
    let price: number;
    let greeks: QuoteResponse["greeks"];
    let spotPrice: number | undefined;
    let iv: number | undefined;

    if (isBuyingOption) {
      // User BUYING options (paying sellToken, receiving buyToken/options)
      optionAddress = normalizedBuyToken;
      const option = this.pricer.getOption(optionAddress);
      if (!option) throw new Error("Option not found");

      const priceResult = this.pricer.price(optionAddress);
      if (!priceResult) throw new Error("Unable to price option - check spot price");

      price = priceResult.ask;
      spotPrice = priceResult.spotPrice;
      iv = priceResult.iv;
      greeks = {
        delta: priceResult.delta,
        gamma: priceResult.gamma,
        theta: priceResult.theta,
        vega: priceResult.vega,
      };

      if (normalizedBuyAmount) {
        buyAmountBigInt = BigInt(normalizedBuyAmount);
        const cost = this.pricer.getAskQuote(optionAddress, buyAmountBigInt, 6);
        if (cost === null) throw new Error("Unable to calculate cost");
        sellAmountBigInt = cost;
      } else {
        sellAmountBigInt = BigInt(normalizedSellAmount!);
        const askPriceScaled = BigInt(Math.floor(price * 1e6));
        buyAmountBigInt = (sellAmountBigInt * BigInt(10 ** option.decimals)) / askPriceScaled;
      }
    } else {
      // User SELLING options (paying options, receiving buyToken)
      optionAddress = normalizedSellToken;
      const option = this.pricer.getOption(optionAddress);
      if (!option) throw new Error("Option not found");

      const priceResult = this.pricer.price(optionAddress);
      if (!priceResult) throw new Error("Unable to price option - check spot price");

      price = priceResult.bid;
      spotPrice = priceResult.spotPrice;
      iv = priceResult.iv;
      greeks = {
        delta: priceResult.delta,
        gamma: priceResult.gamma,
        theta: priceResult.theta,
        vega: priceResult.vega,
      };

      if (normalizedSellAmount) {
        sellAmountBigInt = BigInt(normalizedSellAmount);
        const payout = this.pricer.getBidQuote(optionAddress, sellAmountBigInt, 6);
        if (payout === null) throw new Error("Unable to calculate payout");
        buyAmountBigInt = payout;
      } else {
        buyAmountBigInt = BigInt(normalizedBuyAmount!);
        const bidPriceScaled = BigInt(Math.floor(price * 1e6));
        sellAmountBigInt = (buyAmountBigInt * BigInt(10 ** option.decimals)) / bidPriceScaled;
      }
    }

    const quoteId = `${Date.now()}-${Math.random().toString(36).substr(2, 9)}`;
    // 5-minute quote TTL leaves room for wallet confirmation + tx propagation
    // without tripping Bebop's OrderExpired() on settlement.
    const expiry = Math.floor(Date.now() / 1000) + 300;

    const response: QuoteResponse = {
      quoteId,
      buyToken: normalizedBuyToken,
      sellToken: normalizedSellToken,
      buyAmount: buyAmountBigInt.toString(),
      sellAmount: sellAmountBigInt.toString(),
      price: price.toFixed(6),
      expiry,
      makerAddress: this.makerAddress,
      greeks,
      spotPrice,
      iv,
      routes: ["RFQ"],
      estimatedGas: "150000",
    };

    if (this.signer) {
      // 256-bit nonce built from timestamp + random — unique per quote without a DB.
      const nonce = (BigInt(Date.now()) << 128n) | BigInt(Math.floor(Math.random() * Number.MAX_SAFE_INTEGER));
      const order = {
        partner_id: "0",
        expiry: expiry.toString(),
        taker_address: normalizedTaker,
        maker_address: this.makerAddress,
        maker_nonce: nonce.toString(),
        taker_token: normalizedSellToken,
        maker_token: normalizedBuyToken,
        taker_amount: sellAmountBigInt.toString(),
        maker_amount: buyAmountBigInt.toString(),
        receiver: normalizedTaker,
        packed_commands: "0",
      };
      const { signature } = await this.signer({
        chain_id: this.chainId,
        order_signing_type: "SingleOrder",
        order_type: "Single",
        onchain_partner_id: 0,
        expiry,
        taker_address: order.taker_address,
        maker_address: order.maker_address,
        maker_nonce: order.maker_nonce,
        receiver: order.receiver,
        packed_commands: order.packed_commands,
        quotes: [
          {
            taker_token: order.taker_token,
            maker_token: order.maker_token,
            taker_amount: order.taker_amount,
            maker_amount: order.maker_amount,
          },
        ],
      });
      response.signature = signature;
      response.signScheme = "EIP712";
      response.order = order;
    }

    return response;
  }

  public start(): void {
    this.app.listen(this.config.port, "0.0.0.0", () => {
      console.log(`Quote server listening on port ${this.config.port}`);
      console.log(`  Health:  http://localhost:${this.config.port}/health`);
      console.log(`  Options: http://localhost:${this.config.port}/options`);
      console.log(`  Quote:   http://localhost:${this.config.port}/quote`);
    });
  }

  public listen(port: number): void {
    this.config.port = port;
    this.start();
  }
}

// Factory function for createHttpApi
export function createHttpApi(pricer: Pricer): QuoteServer {
  const makerAddress = process.env.MAKER_ADDRESS || "0x0000000000000000000000000000000000000000";
  const chainId = parseInt(process.env.CHAIN_ID || "1");
  const port = parseInt(process.env.HTTP_PORT || "3010");

  // Capture the key in a closure at construction time so it never reaches
  // QuoteServer (no class property, no config field). Read from env locally
  // and let GC collect the local binding after the closure is built.
  let signer: Signer | undefined;
  {
    const pk = process.env.PRIVATE_KEY;
    if (pk) {
      signer = data => signQuote(data, pk);
    }
  }

  return new QuoteServer({ pricer, makerAddress, chainId, port, signer });
}
