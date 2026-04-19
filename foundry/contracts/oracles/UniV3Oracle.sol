// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { IPriceOracle } from "./IPriceOracle.sol";
import { TickMath } from "../libraries/TickMath.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

interface IUniswapV3Pool {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function observe(uint32[] calldata secondsAgos)
        external
        view
        returns (int56[] memory tickCumulatives, uint160[] memory secondsPerLiquidityCumulativeX128s);
}

/// @title UniV3Oracle
/// @notice Settlement oracle backed by a Uniswap v3 pool's TWAP observation buffer.
/// @dev Reads `pool.observe()` to compute an arithmetic-mean tick over a configurable window
///      ending at the option's expiration. The window provides manipulation resistance:
///      shorter windows are cheaper to poison, longer windows require more stored observations.
///
///      Price output semantics: 18-decimal fixed point, "consideration per collateral".
///      Matches the strike encoding used by OptionFactory / Option / Redemption.
///
///      Token ordering: Uniswap pools store tokens in lexicographic order. This contract
///      handles both cases (collateral as token0 or token1) and inverts the raw ratio when
///      collateral is token1. Decimal normalization is applied at the end.
contract UniV3Oracle is IPriceOracle {
    // ============ IMMUTABLES ============

    IUniswapV3Pool public immutable POOL;
    address public immutable COLLATERAL;
    address public immutable CONSIDERATION;
    uint256 public immutable EXPIRATION_TS;
    uint32 public immutable TWAP_WINDOW;
    bool public immutable COLLATERAL_IS_TOKEN0;
    uint8 public immutable COLLATERAL_DECIMALS;
    uint8 public immutable CONSIDERATION_DECIMALS;

    // ============ STATE ============

    uint256 public settledPrice;
    bool public settled;

    // ============ ERRORS ============

    error PoolTokenMismatch();
    error NotExpired();
    error AlreadySettled();
    error NotSettled();
    error WindowTooLong();

    // ============ EVENTS ============

    event Settled(uint256 price, int24 avgTick);

    // ============ CONSTRUCTOR ============

    /// @param pool_         Uniswap v3 pool with (collateral, consideration) liquidity
    /// @param collateral_   Collateral token address (must be one of pool.token0/token1)
    /// @param consideration_ Consideration token address (the other pool token)
    /// @param expiration_   Option expiration timestamp — TWAP ends here
    /// @param twapWindow_   TWAP window in seconds (e.g., 60 for 1-min, 1800 for 30-min)
    constructor(address pool_, address collateral_, address consideration_, uint256 expiration_, uint32 twapWindow_) {
        POOL = IUniswapV3Pool(pool_);
        EXPIRATION_TS = expiration_;
        TWAP_WINDOW = twapWindow_;
        COLLATERAL = collateral_;
        CONSIDERATION = consideration_;

        address token0 = POOL.token0();
        address token1 = POOL.token1();
        if (!((token0 == collateral_ && token1 == consideration_)
                    || (token1 == collateral_ && token0 == consideration_))) {
            revert PoolTokenMismatch();
        }
        COLLATERAL_IS_TOKEN0 = token0 == collateral_;

        COLLATERAL_DECIMALS = IERC20Metadata(collateral_).decimals();
        CONSIDERATION_DECIMALS = IERC20Metadata(consideration_).decimals();
    }

    // ============ IPriceOracle ============

    function expiration() external view returns (uint256) {
        return EXPIRATION_TS;
    }

    function isSettled() external view returns (bool) {
        return settled;
    }

    /// @notice Settles the oracle by reading a TWAP from `pool.observe()`.
    /// @dev `hint` is ignored (Uniswap needs no external input). Observation window:
    ///      `[expiration - window, expiration]`. Must be called before observations roll off the
    ///      pool's ring buffer — in practice within `observationCardinality * avg_block_time` of
    ///      expiration. Idempotent: no-op after first successful settle.
    function settle(
        bytes calldata /* hint */
    )
        external
        returns (uint256)
    {
        if (settled) return settledPrice;
        if (block.timestamp < EXPIRATION_TS) revert NotExpired();

        // Map expiration to `secondsAgo` for the pool's observation buffer.
        //   secondsAgos[0] = older endpoint  (expiration - window)
        //   secondsAgos[1] = newer endpoint  (expiration)
        uint256 delta = block.timestamp - EXPIRATION_TS;
        uint32 ago = delta > type(uint32).max ? type(uint32).max : uint32(delta);
        uint32 older = ago + TWAP_WINDOW;
        if (older <= ago) revert WindowTooLong(); // overflow guard

        uint32[] memory secondsAgos = new uint32[](2);
        secondsAgos[0] = older;
        secondsAgos[1] = ago;

        (int56[] memory tickCumulatives,) = POOL.observe(secondsAgos);
        int56 tickDelta = tickCumulatives[1] - tickCumulatives[0];
        int24 avgTick = int24(tickDelta / int56(int32(TWAP_WINDOW)));

        // Round toward negative infinity for negative ticks (Uniswap convention).
        if (tickDelta < 0 && (tickDelta % int56(int32(TWAP_WINDOW)) != 0)) {
            avgTick--;
        }

        uint256 p = _tickToPriceWad(avgTick);
        settledPrice = p;
        settled = true;
        emit Settled(p, avgTick);
        return p;
    }

    function price() external view returns (uint256) {
        if (!settled) revert NotSettled();
        return settledPrice;
    }

    // ============ INTERNAL ============

    /// @dev Convert a Uniswap v3 tick to an 18-decimal "consideration per collateral" price.
    ///      Uniswap gives sqrt(token1/token0) in Q64.96. We:
    ///        1. Square to get the raw token1/token0 ratio (×1e18 for precision).
    ///        2. Invert if collateral is token1.
    ///        3. Normalize decimals: result *= 10^collDec / 10^consDec.
    function _tickToPriceWad(int24 tick) internal view returns (uint256) {
        uint256 sqrtP = uint256(TickMath.getSqrtPriceAtTick(tick));
        // rawRatioWad = (token1/token0) * 1e18 — use two-step mulDiv to avoid overflow
        uint256 r = Math.mulDiv(sqrtP, sqrtP, 1 << 96);
        uint256 token1PerToken0Wad = Math.mulDiv(r, 1e18, 1 << 96);

        // Select "consideration per collateral" scaled by 1e18
        uint256 consPerCollWad;
        if (COLLATERAL_IS_TOKEN0) {
            // token1 = consideration, token0 = collateral → raw ratio IS what we want
            consPerCollWad = token1PerToken0Wad;
        } else {
            // token1 = collateral, token0 = consideration → invert
            // safe: sqrtP > 0 ensures token1PerToken0Wad > 0
            consPerCollWad = (1e18 * 1e18) / token1PerToken0Wad;
        }

        // Decimal normalization: price_18dec = consPerCollWad * 10^collDec / 10^consDec
        return Math.mulDiv(consPerCollWad, 10 ** COLLATERAL_DECIMALS, 10 ** CONSIDERATION_DECIMALS);
    }
}
