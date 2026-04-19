import { blackScholes, calculateGreeks, type BlackScholesInput } from "./blackScholes";
import type { OptionParams, PriceResult, MarketData, SpreadConfig } from "./types";
import type { SpotFeed } from "./spotFeed";

export interface PricerConfig {
  spreadConfig?: SpreadConfig;
  riskFreeRate?: number;
  defaultIV?: number;
  spotFeed?: SpotFeed;
}

const DEFAULT_SPREAD_CONFIG: SpreadConfig = {
  bidSpread: 0.02, // 2% below mid
  askSpread: 0.02, // 2% above mid
  minSpread: 0.001, // Minimum $0.001 spread (reduced to avoid large % spreads on cheap options)
};

/**
 * Option Pricer using Black-Scholes model
 */
export class Pricer {
  private options: Map<string, OptionParams> = new Map();
  private spotPrices: Map<string, number> = new Map();
  private ivOverrides: Map<string, number> = new Map();
  private spreadConfig: SpreadConfig;
  private riskFreeRate: number;
  private defaultIV: number;
  private spotFeed?: SpotFeed;

  constructor(config: PricerConfig = {}) {
    this.spreadConfig = config.spreadConfig ?? DEFAULT_SPREAD_CONFIG;
    this.riskFreeRate = config.riskFreeRate ?? 0.05; // 5% default
    this.defaultIV = config.defaultIV ?? 0.80; // 80% default IV for crypto
    this.spotFeed = config.spotFeed;
  }

  /**
   * Register an option contract
   */
  registerOption(option: OptionParams): void {
    this.options.set(option.optionAddress.toLowerCase(), option);
  }

  /**
   * Register multiple option contracts
   */
  registerOptions(options: OptionParams[]): void {
    for (const option of options) {
      this.registerOption(option);
    }
  }

  /**
   * Get registered option by address
   */
  getOption(address: string): OptionParams | undefined {
    return this.options.get(address.toLowerCase());
  }

  /**
   * Get all registered options
   */
  getAllOptions(): OptionParams[] {
    return Array.from(this.options.values());
  }

  /**
   * Get all registered option addresses
   */
  getOptionAddresses(): string[] {
    return Array.from(this.options.keys());
  }

  /**
   * Get pricing for an option (for pricing stream)
   * Returns bids/asks in [price, size] format
   */
  getPrice(optionAddress: string): { bids: [number, number][]; asks: [number, number][] } | null {
    const priceResult = this.price(optionAddress);
    if (!priceResult) return null;

    return {
      bids: [[priceResult.bid, 1000]],
      asks: [[priceResult.ask, 1000]],
    };
  }

  /**
   * Check if an address is a registered option
   */
  isOption(address: string): boolean {
    return this.options.has(address.toLowerCase());
  }

  /**
   * Update spot price for an underlying
   */
  setSpotPrice(underlying: string, price: number): void {
    this.spotPrices.set(underlying.toUpperCase(), price);
  }

  /**
   * Get spot price for an underlying
   */
  getSpotPrice(underlying: string): number | undefined {
    return this.spotPrices.get(underlying.toUpperCase());
  }

  /**
   * Override IV for a specific option
   */
  setIV(optionAddress: string, iv: number): void {
    this.ivOverrides.set(optionAddress.toLowerCase(), iv);
  }

  /**
   * Get IV for an option (override or default)
   */
  getIV(optionAddress: string): number {
    return this.ivOverrides.get(optionAddress.toLowerCase()) ?? this.defaultIV;
  }

  /**
   * Calculate time to expiry in years
   */
  private timeToExpiry(expiryTimestamp: number): number {
    const now = Date.now() / 1000;
    const secondsToExpiry = Math.max(0, expiryTimestamp - now);
    return secondsToExpiry / (365 * 24 * 60 * 60);
  }

  /**
   * Price an option contract
   */
  price(optionAddress: string): PriceResult | null {
    const option = this.getOption(optionAddress);
    if (!option) return null;

    const spotPrice = this.getSpotPrice(option.underlying);
    if (spotPrice === undefined) return null;

    const T = this.timeToExpiry(option.expiry);
    const sigma = this.getIV(optionAddress);

    const bsInput: BlackScholesInput = {
      S: spotPrice,
      K: option.strike,
      T,
      r: this.riskFreeRate,
      sigma,
    };

    const bsResult = blackScholes(bsInput);
    const greeks = calculateGreeks(bsInput, option.isPut);

    const mid = option.isPut ? bsResult.putPrice : bsResult.callPrice;

    // Calculate bid/ask with spreads
    let bidSpreadAmount = mid * this.spreadConfig.bidSpread;
    let askSpreadAmount = mid * this.spreadConfig.askSpread;

    // Ensure minimum spread
    bidSpreadAmount = Math.max(bidSpreadAmount, this.spreadConfig.minSpread / 2);
    askSpreadAmount = Math.max(askSpreadAmount, this.spreadConfig.minSpread / 2);

    const bid = Math.max(0, mid - bidSpreadAmount);
    const ask = mid + askSpreadAmount;

    return {
      bid,
      ask,
      mid,
      delta: greeks.delta,
      gamma: greeks.gamma,
      theta: greeks.theta,
      vega: greeks.vega,
      iv: sigma,
      spotPrice,
      timeToExpiry: T,
    };
  }

  /**
   * Get quote for buying options (user pays, receives options)
   * Returns the cost in consideration token (e.g., USDC)
   */
  getAskQuote(optionAddress: string, amount: bigint, decimals: number): bigint | null {
    const priceResult = this.price(optionAddress);
    if (!priceResult) return null;

    // Convert: (amount * askPrice * 10^decimals) / 10^optionDecimals
    const option = this.getOption(optionAddress);
    if (!option) return null;

    const askPriceScaled = BigInt(Math.floor(priceResult.ask * 10 ** decimals));
    const cost = (amount * askPriceScaled) / BigInt(10 ** option.decimals);

    return cost;
  }

  /**
   * Get quote for selling options (user sells options, receives consideration)
   * Returns the payout in consideration token (e.g., USDC)
   */
  getBidQuote(optionAddress: string, amount: bigint, decimals: number): bigint | null {
    const priceResult = this.price(optionAddress);
    if (!priceResult) return null;

    const option = this.getOption(optionAddress);
    if (!option) return null;

    const bidPriceScaled = BigInt(Math.floor(priceResult.bid * 10 ** decimals));
    const payout = (amount * bidPriceScaled) / BigInt(10 ** option.decimals);

    return payout;
  }

  /**
   * Update spread configuration
   */
  setSpreadConfig(config: Partial<SpreadConfig>): void {
    this.spreadConfig = { ...this.spreadConfig, ...config };
  }

  /**
   * Update risk-free rate
   */
  setRiskFreeRate(rate: number): void {
    this.riskFreeRate = rate;
  }

  /**
   * Get market data summary
   */
  getMarketData(underlying: string): MarketData | null {
    const spotPrice = this.getSpotPrice(underlying);
    if (spotPrice === undefined) return null;

    return {
      spotPrice,
      riskFreeRate: this.riskFreeRate,
      impliedVolatility: this.defaultIV,
    };
  }

  /**
   * Handle RFQ request (for Bebop integration)
   * Returns quote response or decline
   */
  async handleRfq(rfq: any): Promise<any> {
    const { buy_tokens, sell_tokens, rfq_id, taker_address, _originalRequest } = rfq;

    // Log RFQ for debugging
    console.log(`\n📝 RFQ ${rfq_id.substring(0, 8)}:`);
    console.log(`  Buy: ${buy_tokens?.[0]?.amount} of ${buy_tokens?.[0]?.token?.substring(0, 8)}`);
    console.log(`  Sell: ${sell_tokens?.[0]?.amount} of ${sell_tokens?.[0]?.token?.substring(0, 8)}`);

    // Validate tokens
    const buyToken = buy_tokens?.[0];
    const sellToken = sell_tokens?.[0];

    if (!buyToken || !sellToken) {
      console.log(`❌ Decline: Invalid tokens`);
      return {
        type: "decline",
        rfq_id,
        reason: "Invalid tokens",
      };
    }

    // Determine which token is the option
    const isBuyingOption = this.isOption(buyToken.token);
    const isSellingOption = this.isOption(sellToken.token);

    if (!isBuyingOption && !isSellingOption) {
      console.log(`❌ Decline: No option token found`);
      return {
        type: "decline",
        rfq_id,
        reason: "No option token in request",
      };
    }

    if (isBuyingOption && isSellingOption) {
      console.log(`❌ Decline: Both tokens are options`);
      return {
        type: "decline",
        rfq_id,
        reason: "Cannot trade option for option",
      };
    }

    try {
      const makerAddress = process.env.MAKER_ADDRESS;
      if (!makerAddress) {
        throw new Error("MAKER_ADDRESS not set");
      }

      // Determine trade direction and calculate quote
      let quoteResponse;
      if (isBuyingOption) {
        // Taker wants to buy options, maker sells options (asks)
        // Taker pays sellToken, receives buyToken (options)
        const optionAddress = buyToken.token;
        const optionAmount = BigInt(buyToken.amount);
        const option = this.getOption(optionAddress);

        if (!option) {
          throw new Error("Option not found in registry");
        }

        // Calculate how much consideration (USDC) the taker needs to pay
        // Using ask price since maker is selling
        const considerationAmount = this.getAskQuote(optionAddress, optionAmount, 6); // USDC has 6 decimals

        if (!considerationAmount) {
          throw new Error("Failed to calculate quote");
        }

        console.log(`💰 Quote: Sell ${optionAmount} options for ${considerationAmount} USDC`);

        quoteResponse = {
          type: "quote",
          rfq_id,
          maker_address: makerAddress,
          buy_tokens: [{ token: sellToken.token, amount: considerationAmount.toString() }],
          sell_tokens: [{ token: buyToken.token, amount: optionAmount.toString() }],
          expiry: Math.floor(Date.now() / 1000) + 60, // 60 second expiry
          _originalRequest,
        };
      } else {
        // Taker wants to sell options, maker buys options (bids)
        // Taker pays buyToken (options), receives sellToken
        const optionAddress = sellToken.token;
        const optionAmount = BigInt(sellToken.amount);
        const option = this.getOption(optionAddress);

        if (!option) {
          throw new Error("Option not found in registry");
        }

        // Calculate how much consideration (USDC) the maker will pay
        // Using bid price since maker is buying
        const considerationAmount = this.getBidQuote(optionAddress, optionAmount, 6); // USDC has 6 decimals

        if (!considerationAmount) {
          throw new Error("Failed to calculate quote");
        }

        console.log(`💰 Quote: Buy ${optionAmount} options for ${considerationAmount} USDC`);

        quoteResponse = {
          type: "quote",
          rfq_id,
          maker_address: makerAddress,
          buy_tokens: [{ token: sellToken.token, amount: optionAmount.toString() }],
          sell_tokens: [{ token: buyToken.token, amount: considerationAmount.toString() }],
          expiry: Math.floor(Date.now() / 1000) + 60, // 60 second expiry
          _originalRequest,
        };
      }

      // Sign the quote if private key is available
      const privateKey = process.env.PRIVATE_KEY;
      if (privateKey && _originalRequest) {
        const { signQuote } = await import("../bebop/signing");
        const quoteData = {
          chain_id: rfq.chain_id,
          order_signing_type: _originalRequest.order_signing_type || "SingleOrder",
          order_type: _originalRequest.order_type || "Single",
          onchain_partner_id: _originalRequest.onchain_partner_id || 0,
          expiry: quoteResponse.expiry,
          taker_address: taker_address,
          maker_address: makerAddress,
          maker_nonce: _originalRequest.maker_nonce || "0",
          receiver: _originalRequest.receiver || taker_address,
          packed_commands: _originalRequest.packed_commands || "0",
          quotes: [
            {
              taker_token: quoteResponse.buy_tokens[0].token,
              maker_token: quoteResponse.sell_tokens[0].token,
              taker_amount: quoteResponse.buy_tokens[0].amount,
              maker_amount: quoteResponse.sell_tokens[0].amount,
            },
          ],
        };

        const { signature } = await signQuote(quoteData, privateKey);
        (quoteResponse as any).signature = signature;
        console.log(`✍️  Quote signed`);
      }

      console.log(`✅ Quote sent`);
      return quoteResponse;
    } catch (error) {
      console.error(`❌ Error generating quote:`, error);
      return {
        type: "decline",
        rfq_id,
        reason: `Error: ${(error as Error).message}`,
      };
    }
  }
}
