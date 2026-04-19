import { maxUint256 } from "viem";

/** Maximum uint256 value for unlimited approvals */
export const MAX_UINT256 = maxUint256;

/** Strike price decimal precision (18 decimals) */
export const STRIKE_DECIMALS = 18;

/** Strike decimal multiplier as bigint */
export const STRIKE_MULTIPLIER = 10n ** BigInt(STRIKE_DECIMALS);

/** Convert a human-readable strike price to contract format (18 decimals) */
export function toStrikePrice(price: number): bigint {
  return BigInt(Math.floor(price * 10 ** STRIKE_DECIMALS));
}

/** Convert contract strike price to human-readable format */
export function fromStrikePrice(strike: bigint): number {
  return Number(strike) / 10 ** STRIKE_DECIMALS;
}

/**
 * Calculate consideration amount from collateral amount based on strike price
 * Formula: (collAmount * strike * 10^consDecimals) / (10^strikeDecimals * 10^collDecimals)
 */
export function toConsideration(
  collateralAmount: bigint,
  strike: bigint,
  collateralDecimals: number,
  considerationDecimals: number,
): bigint {
  return (
    (collateralAmount * strike * 10n ** BigInt(considerationDecimals)) /
    (STRIKE_MULTIPLIER * 10n ** BigInt(collateralDecimals))
  );
}

/**
 * Calculate collateral amount from consideration amount based on strike price
 * Formula: (consAmount * 10^strikeDecimals * 10^collDecimals) / (strike * 10^consDecimals)
 */
export function toCollateral(
  considerationAmount: bigint,
  strike: bigint,
  collateralDecimals: number,
  considerationDecimals: number,
): bigint {
  if (strike === 0n) return 0n;
  return (
    (considerationAmount * STRIKE_MULTIPLIER * 10n ** BigInt(collateralDecimals)) /
    (strike * 10n ** BigInt(considerationDecimals))
  );
}
