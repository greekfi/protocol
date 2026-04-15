// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { TickMath } from "@uniswap/v4-core/src/libraries/TickMath.sol";

import { IOption } from "./interfaces/IOption.sol";

interface IBlackScholes {
    function priceWithSmile(
        uint256 spot,
        uint256 strike,
        uint256 timeToExpiry,
        uint256 atmVol,
        uint256 rate,
        bool isPut,
        int256 skew,
        int256 kurtosis
    ) external pure returns (uint256);
}

interface IUniswapV3PoolOracle {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function observe(uint32[] calldata secondsAgos)
        external
        view
        returns (int56[] memory tickCumulatives, uint160[] memory secondsPerLiquidityCumulativeX128s);
}

/// @title OptionPricer
/// @notice All option pricing logic: TWAP oracle, Black-Scholes, inventory spread, decimal conversion.
///         The vault calls pricer.price() and gets back output amounts. Clean separation.
contract OptionPricer is Ownable {
    using Math for uint256;

    // ============ ERRORS ============

    error InvalidAddress();
    error InvalidBps();

    // ============ EVENTS ============

    event VolatilityUpdated(uint256 oldVol, uint256 newVol);
    event RiskFreeRateUpdated(uint256 oldRate, uint256 newRate);
    event SpreadUpdated(uint256 oldSpread, uint256 newSpread);
    event SkewUpdated(int256 oldSkew, int256 newSkew);
    event KurtosisUpdated(int256 oldKurtosis, int256 newKurtosis);
    event InventorySkewFactorUpdated(uint256 oldFactor, uint256 newFactor);

    // ============ STATE ============

    IBlackScholes public blackScholes;
    IUniswapV3PoolOracle public pricePool;
    address public collateral;
    uint256 public volatility;
    uint256 public riskFreeRate;
    uint32 public twapWindow;
    uint256 public spreadBps;
    int256 public skew;
    int256 public kurtosis;
    uint256 public inventorySkewFactor;

    // ============ CONSTRUCTOR ============

    constructor(address blackScholes_, address pricePool_, address collateral_, uint32 twapWindow_)
        Ownable(msg.sender)
    {
        if (blackScholes_ == address(0) || pricePool_ == address(0) || collateral_ == address(0)) {
            revert InvalidAddress();
        }
        blackScholes = IBlackScholes(blackScholes_);
        pricePool = IUniswapV3PoolOracle(pricePool_);
        collateral = collateral_;
        twapWindow = twapWindow_;

        volatility = 0.2e18;
        riskFreeRate = 0.05e18;
    }

    // ============ PRICING ============

    /// @notice Get a price quote for an option with inventory-based spread
    /// @param option Option contract address
    /// @param amount Input amount (cash decimals if isBuy, 18 decimals if !isBuy)
    /// @param isBuy true = user buying options (ask), false = user selling (bid)
    /// @param netInventory Vault's net inventory (positive = net short)
    /// @param totalAssets Vault's total assets for inventory normalization
    function price(address option, uint256 amount, bool isBuy, int256 netInventory, uint256 totalAssets)
        external
        view
        returns (uint256 outputAmount, uint256 unitPrice)
    {
        IOption opt = IOption(option);
        uint256 spot = getCollateralPrice();
        uint256 timeToExpiry = opt.expirationDate() > block.timestamp ? opt.expirationDate() - block.timestamp : 0;

        uint256 midPrice = blackScholes.priceWithSmile(
            spot, opt.strike(), timeToExpiry, volatility, riskFreeRate, opt.isPut(), skew, kurtosis
        );

        uint256 halfSpread = _calculateHalfSpread(netInventory, totalAssets);
        uint256 bsPrice;
        if (isBuy) {
            bsPrice = Math.mulDiv(midPrice, 10000 + halfSpread, 10000);
        } else {
            bsPrice = Math.mulDiv(midPrice, 10000 - halfSpread, 10000);
        }

        uint256 cashDecimals = IERC20Metadata(opt.consideration()).decimals();
        uint256 scaleFactor = 10 ** (36 - cashDecimals);

        if (isBuy) {
            outputAmount = Math.mulDiv(amount, scaleFactor, bsPrice);
        } else {
            outputAmount = Math.mulDiv(amount, bsPrice, scaleFactor);
        }

        unitPrice = Math.mulDiv(bsPrice, 10 ** cashDecimals, 1e18);
    }

    /// @notice Get collateral price via Uniswap v3 TWAP
    function getCollateralPrice() public view returns (uint256 price_) {
        uint32[] memory secondsAgos = new uint32[](2);
        secondsAgos[0] = twapWindow;
        secondsAgos[1] = 0;

        (int56[] memory tickCumulatives,) = pricePool.observe(secondsAgos);

        int24 meanTick = int24((tickCumulatives[1] - tickCumulatives[0]) / int56(int32(twapWindow)));
        uint160 sqrtPriceX96 = TickMath.getSqrtPriceAtTick(meanTick);

        uint256 sqrtPriceX32 = uint256(sqrtPriceX96) >> 64;
        uint256 priceX64 = sqrtPriceX32 * sqrtPriceX32;
        price_ = (priceX64 * 1e18) >> 64;

        uint256 decimals0 = IERC20Metadata(pricePool.token0()).decimals();
        uint256 decimals1 = IERC20Metadata(pricePool.token1()).decimals();
        if (decimals1 > decimals0) {
            price_ = price_ / (10 ** (decimals1 - decimals0));
        } else if (decimals0 > decimals1) {
            price_ = price_ * (10 ** (decimals0 - decimals1));
        }

        bool collateralIsToken1 = pricePool.token1() == collateral;
        if (collateralIsToken1) {
            require(price_ > 0, "Price cannot be zero for inverse");
            price_ = 1e36 / price_;
        }
    }

    // ============ INTERNAL ============

    function _calculateHalfSpread(int256 netInventory, uint256 totalAssets) internal view returns (uint256) {
        uint256 baseHalf = spreadBps / 2;
        if (totalAssets == 0 || inventorySkewFactor == 0) return baseHalf;
        uint256 absInventory = netInventory >= 0 ? uint256(netInventory) : uint256(-netInventory);
        return baseHalf + (inventorySkewFactor * absInventory) / totalAssets;
    }

    // ============ ADMIN ============

    function setBlackScholes(address bs) external onlyOwner {
        if (bs == address(0)) revert InvalidAddress();
        blackScholes = IBlackScholes(bs);
    }

    function setPricePool(address pool) external onlyOwner {
        if (pool == address(0)) revert InvalidAddress();
        pricePool = IUniswapV3PoolOracle(pool);
    }

    function setCollateral(address collateral_) external onlyOwner {
        if (collateral_ == address(0)) revert InvalidAddress();
        collateral = collateral_;
    }

    function setVolatility(uint256 vol) external onlyOwner {
        uint256 old = volatility;
        volatility = vol;
        emit VolatilityUpdated(old, vol);
    }

    function setRiskFreeRate(uint256 rate) external onlyOwner {
        uint256 old = riskFreeRate;
        riskFreeRate = rate;
        emit RiskFreeRateUpdated(old, rate);
    }

    function setTwapWindow(uint32 window) external onlyOwner {
        twapWindow = window;
    }

    function setSpreadBps(uint256 bps) external onlyOwner {
        if (bps > 5000) revert InvalidBps();
        uint256 old = spreadBps;
        spreadBps = bps;
        emit SpreadUpdated(old, bps);
    }

    function setSkew(int256 skew_) external onlyOwner {
        int256 old = skew;
        skew = skew_;
        emit SkewUpdated(old, skew_);
    }

    function setKurtosis(int256 kurtosis_) external onlyOwner {
        int256 old = kurtosis;
        kurtosis = kurtosis_;
        emit KurtosisUpdated(old, kurtosis_);
    }

    function setInventorySkewFactor(uint256 factor) external onlyOwner {
        uint256 old = inventorySkewFactor;
        inventorySkewFactor = factor;
        emit InventorySkewFactorUpdated(old, factor);
    }
}
