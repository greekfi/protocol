import { blackScholes, calculateGreeks, type BlackScholesInput } from "./blackScholes";
import type { OptionParams, PriceResult, MarketData, SpreadConfig } from "./types";

export interface PricerConfig {
  spreadConfig?: SpreadConfig;
  riskFreeRate?: number;
  defaultIV?: number;
}

const DEFAULT_SPREAD_CONFIG: SpreadConfig = {
  bidSpread: 0.02, // 2% below mid
  askSpread: 0.02, // 2% above mid
  minSpread: 0.01, // Minimum $0.01 spread
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

  constructor(config: PricerConfig = {}) {
    this.spreadConfig = config.spreadConfig ?? DEFAULT_SPREAD_CONFIG;
    this.riskFreeRate = config.riskFreeRate ?? 0.05; // 5% default
    this.defaultIV = config.defaultIV ?? 0.80; // 80% default IV for crypto
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
}
