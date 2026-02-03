// Black-Scholes option pricing with 100% volatility

// Standard normal cumulative distribution function
function normalCDF(x: number): number {
  const a1 = 0.254829592;
  const a2 = -0.284496736;
  const a3 = 1.421413741;
  const a4 = -1.453152027;
  const a5 = 1.061405429;
  const p = 0.3275911;

  const sign = x < 0 ? -1 : 1;
  x = Math.abs(x) / Math.sqrt(2);

  const t = 1.0 / (1.0 + p * x);
  const y = 1.0 - ((((a5 * t + a4) * t + a3) * t + a2) * t + a1) * t * Math.exp(-x * x);

  return 0.5 * (1.0 + sign * y);
}

export interface BlackScholesParams {
  spot: number;        // Current price of underlying (e.g., ETH price in USD)
  strike: number;      // Strike price
  timeToExpiry: number; // Time to expiration in years
  volatility: number;  // Implied volatility (1.0 = 100%)
  riskFreeRate: number; // Risk-free rate (e.g., 0.05 = 5%)
  isPut: boolean;
}

export function blackScholesPrice(params: BlackScholesParams): number {
  const { spot, strike, timeToExpiry, volatility, riskFreeRate, isPut } = params;

  // Handle edge cases
  if (timeToExpiry <= 0) {
    // Option has expired - return intrinsic value
    if (isPut) {
      return Math.max(strike - spot, 0);
    } else {
      return Math.max(spot - strike, 0);
    }
  }

  if (spot <= 0 || strike <= 0) {
    return 0;
  }

  const sqrtT = Math.sqrt(timeToExpiry);
  const d1 = (Math.log(spot / strike) + (riskFreeRate + 0.5 * volatility * volatility) * timeToExpiry) / (volatility * sqrtT);
  const d2 = d1 - volatility * sqrtT;

  const discountFactor = Math.exp(-riskFreeRate * timeToExpiry);

  if (isPut) {
    // Put option: K*e^(-rT)*N(-d2) - S*N(-d1)
    return strike * discountFactor * normalCDF(-d2) - spot * normalCDF(-d1);
  } else {
    // Call option: S*N(d1) - K*e^(-rT)*N(d2)
    return spot * normalCDF(d1) - strike * discountFactor * normalCDF(d2);
  }
}

// Calculate bid/ask with a spread
export function calculateBidAsk(
  spot: number,
  strike: number,
  expirationTimestamp: number, // Unix timestamp
  isPut: boolean,
  volatility: number = 1.0, // 100% vol
  riskFreeRate: number = 0.05, // 5%
  spreadPercent: number = 0.02 // 2% spread
): { bid: number; ask: number } {
  const now = Date.now() / 1000;
  const timeToExpiry = Math.max(0, (expirationTimestamp - now) / (365 * 24 * 60 * 60)); // Convert to years

  let midPrice = blackScholesPrice({
    spot,
    strike,
    timeToExpiry,
    volatility,
    riskFreeRate,
    isPut,
  });

  // For puts: 1 option token = right to sell (1/strike) of underlying
  // So put price per token = BS price / strike
  if (isPut && strike > 0) {
    midPrice = midPrice / strike;
  }

  // Apply spread around mid price
  const halfSpread = midPrice * spreadPercent / 2;
  const bid = Math.max(0.01, midPrice - halfSpread); // Minimum bid of $0.01
  const ask = midPrice + halfSpread;

  return { bid, ask };
}
