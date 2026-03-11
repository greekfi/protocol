// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

import { ERC4626 } from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { ReentrancyGuardTransient } from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

import { TickMath } from "@uniswap/v4-core/src/libraries/TickMath.sol";

import { IOption } from "./interfaces/IOption.sol";
import { IOptionFactory } from "./interfaces/IOptionFactory.sol";
import { IStrategyVault } from "./interfaces/IStrategyVault.sol";

using SafeERC20 for IERC20;

interface IBlackScholes {
    function price(uint256 spot, uint256 strike, uint256 timeToExpiry, uint256 vol, uint256 rate, bool isPut)
        external
        pure
        returns (uint256);

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

    function delta(uint256 spot, uint256 strike, uint256 timeToExpiry, uint256 vol, uint256 rate, bool isPut)
        external
        pure
        returns (int256);

    function gamma(uint256 spot, uint256 strike, uint256 timeToExpiry, uint256 vol, uint256 rate)
        external
        pure
        returns (uint256);

    function vega(uint256 spot, uint256 strike, uint256 timeToExpiry, uint256 vol, uint256 rate)
        external
        pure
        returns (uint256);

    function theta(uint256 spot, uint256 strike, uint256 timeToExpiry, uint256 vol, uint256 rate, bool isPut)
        external
        pure
        returns (int256);
}

interface IUniswapV3PoolOracle {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function observe(uint32[] calldata secondsAgos)
        external
        view
        returns (int56[] memory tickCumulatives, uint160[] memory secondsPerLiquidityCumulativeX128s);
}

/// @title StrategyVault
/// @notice ERC4626 vault that writes covered options with integrated pricing and strategy.
/// @dev Combines LP deposits, Black-Scholes pricing (via external contract), and option lifecycle.
///      Depositors provide collateral (e.g. WETH) and earn yield from option premiums.
///      The hook sells options → vault mints & delivers → options expire → settlement returns collateral.
contract StrategyVault is ERC4626, Ownable, ReentrancyGuardTransient, Pausable, IStrategyVault {
    using Math for uint256;

    // ============ PRICING ============

    IBlackScholes public blackScholes;
    IUniswapV3PoolOracle public pricePool;
    uint256 public override volatility;
    uint256 public override riskFreeRate;
    uint32 public twapWindow;
    uint8 internal _cashDecimals;

    // ============ STRATEGY ============

    address public override cashToken;
    IOptionFactory public factory;
    StrikeConfig[] public strikeConfigs;
    uint256 public override rollBounty;
    uint256 public override spreadBps; // total spread in bps (e.g. 100 = 1%, half applied each side)
    int256 public override skew; // vol smile skew (1e18 scale, typically negative for crypto)
    int256 public override kurtosis; // vol smile kurtosis (1e18 scale, typically positive)
    mapping(address => bool) public rolled; // tracks which expired options have been rolled

    // ============ HOOKS ============

    mapping(address => bool) public override authorizedHooks;

    // ============ COMMITMENT CAP ============

    uint256 public maxCommitmentBps;

    // ============ BOOKKEEPING ============

    uint256 public override totalCommitted;
    mapping(address => uint256) public override committed;
    mapping(address => uint256) public trackedRedemptionBalance;
    mapping(address => bool) public override whitelistedOptions;
    uint256 public totalPremiumsCollected;

    // ============ MODIFIERS ============

    modifier onlyHook() {
        if (!authorizedHooks[msg.sender]) revert OnlyHook();
        _;
    }

    // ============ CONSTRUCTOR ============

    /// @param collateral_ Underlying collateral token (e.g. WETH)
    /// @param name_ Vault share token name
    /// @param symbol_ Vault share token symbol
    /// @param factory_ OptionFactory address
    /// @param blackScholes_ BlackScholes pricing contract
    /// @param pricePool_ Uniswap v3 pool for TWAP oracle
    /// @param cashToken_ Cash/consideration token (e.g. USDC)
    /// @param twapWindow_ TWAP window in seconds (e.g. 1800 for 30 min)
    constructor(
        IERC20 collateral_,
        string memory name_,
        string memory symbol_,
        address factory_,
        address blackScholes_,
        address pricePool_,
        address cashToken_,
        uint32 twapWindow_
    ) ERC4626(collateral_) ERC20(name_, symbol_) Ownable(msg.sender) {
        if (
            factory_ == address(0) || blackScholes_ == address(0) || pricePool_ == address(0)
                || cashToken_ == address(0)
        ) {
            revert InvalidAddress();
        }
        factory = IOptionFactory(factory_);
        blackScholes = IBlackScholes(blackScholes_);
        pricePool = IUniswapV3PoolOracle(pricePool_);
        cashToken = cashToken_;
        twapWindow = twapWindow_;
        _cashDecimals = IERC20Metadata(cashToken_).decimals();

        volatility = 0.2e18; // 20% default
        riskFreeRate = 0.05e18; // 5% default
        maxCommitmentBps = 8000; // 80%
    }

    // ============ ERC4626 OVERRIDES ============

    /// @dev Virtual share offset to prevent first-depositor attack
    function _decimalsOffset() internal pure override returns (uint8) {
        return 3;
    }

    function totalAssets() public view override returns (uint256) {
        return IERC20(asset()).balanceOf(address(this)) + totalCommitted;
    }

    function maxWithdraw(address owner_) public view override returns (uint256) {
        uint256 idle = IERC20(asset()).balanceOf(address(this));
        uint256 ownerAssets = _convertToAssets(balanceOf(owner_), Math.Rounding.Floor);
        return Math.min(idle, ownerAssets);
    }

    function maxRedeem(address owner_) public view override returns (uint256) {
        uint256 idle = IERC20(asset()).balanceOf(address(this));
        uint256 idleShares = _convertToShares(idle, Math.Rounding.Floor);
        return Math.min(idleShares, balanceOf(owner_));
    }

    // ============ PRICING ============

    /// @notice Get collateral price via Uniswap v3 TWAP
    /// @return price_ Price of collateral in cash terms, 18 decimals
    function getCollateralPrice() public view override returns (uint256 price_) {
        uint32[] memory secondsAgos = new uint32[](2);
        secondsAgos[0] = twapWindow;
        secondsAgos[1] = 0;

        (int56[] memory tickCumulatives,) = pricePool.observe(secondsAgos);

        int24 meanTick = int24((tickCumulatives[1] - tickCumulatives[0]) / int56(int32(twapWindow)));
        uint160 sqrtPriceX96 = TickMath.getSqrtPriceAtTick(meanTick);

        // Convert sqrtPriceX96 to price (token0 in terms of token1)
        // Use shifted multiplication to avoid overflow
        uint256 sqrtPriceX32 = uint256(sqrtPriceX96) >> 64;
        uint256 priceX64 = sqrtPriceX32 * sqrtPriceX32;
        price_ = (priceX64 * 1e18) >> 64;

        // Decimal adjustment
        uint8 decimals0 = IERC20Metadata(pricePool.token0()).decimals();
        uint8 decimals1 = IERC20Metadata(pricePool.token1()).decimals();
        if (decimals1 > decimals0) {
            price_ = price_ / (10 ** (decimals1 - decimals0));
        } else if (decimals0 > decimals1) {
            price_ = price_ * (10 ** (decimals0 - decimals1));
        }

        // If collateral is token1, invert (price was token0-in-token1)
        bool collateralIsToken1 = pricePool.token1() == asset();
        if (collateralIsToken1) {
            require(price_ > 0, "Price cannot be zero for inverse");
            price_ = 1e36 / price_;
        }
    }

    /// @inheritdoc IStrategyVault
    function getQuote(address option, uint256 amount, bool cashForOption)
        external
        view
        override
        returns (uint256 outputAmount, uint256 unitPrice)
    {
        IOption opt = IOption(option);
        uint256 spot = getCollateralPrice();
        uint256 timeToExpiry = opt.expirationDate() > block.timestamp ? opt.expirationDate() - block.timestamp : 0;

        uint256 midPrice = blackScholes.priceWithSmile(
            spot, opt.strike(), timeToExpiry, volatility, riskFreeRate, opt.isPut(), skew, kurtosis
        );

        // Apply spread: ask = mid * (10000 + halfSpread) / 10000
        //               bid = mid * (10000 - halfSpread) / 10000
        uint256 halfSpread = spreadBps / 2;
        uint256 bsPrice;
        if (cashForOption) {
            // Buying options → ask (higher price, fewer options per cash)
            bsPrice = Math.mulDiv(midPrice, 10000 + halfSpread, 10000);
        } else {
            // Selling options → bid (lower price, less cash per option)
            bsPrice = Math.mulDiv(midPrice, 10000 - halfSpread, 10000);
        }

        // bsPrice is in 1e18 "dollar" terms
        // Scale factor converts between 18-decimal option amounts and cash-decimal amounts
        // scaleFactor = 10^(36 - cashDecimals)
        uint256 scaleFactor = 10 ** (36 - uint256(_cashDecimals));

        if (cashForOption) {
            // amount = cash input (cash decimals), outputAmount = options out (18 decimals)
            outputAmount = Math.mulDiv(amount, scaleFactor, bsPrice);
        } else {
            // amount = options input (18 decimals), outputAmount = cash out (cash decimals)
            outputAmount = Math.mulDiv(amount, bsPrice, scaleFactor);
        }

        // unitPrice = price per option in cash-token units (spread-adjusted)
        unitPrice = Math.mulDiv(bsPrice, 10 ** uint256(_cashDecimals), 1e18);
    }

    // ============ HOOK INTERACTION: MINT AND DELIVER ============

    /// @inheritdoc IStrategyVault
    function mintAndDeliver(address option, uint256 amount, address buyer)
        external
        override
        onlyHook
        nonReentrant
        whenNotPaused
        returns (uint256 delivered)
    {
        if (!whitelistedOptions[option]) revert NotWhitelisted();
        if (amount == 0) revert ZeroAmount();
        if (IOption(option).collateral() != asset()) revert CollateralMismatch();

        // Check commitment cap
        uint256 total = totalAssets();
        if (totalCommitted + amount > (total * maxCommitmentBps) / 10000) revert ExceedsCommitmentCap();

        // Check idle collateral
        uint256 idle = IERC20(asset()).balanceOf(address(this));
        if (amount > idle) revert InsufficientIdle();

        // Snapshot option balance BEFORE mint (fix: only deliver the delta)
        uint256 optBefore = IERC20(option).balanceOf(address(this));

        // Mint: pulls collateral from vault → Redemption contract
        IOption(option).mint(address(this), amount);

        // Deliver only the newly minted option tokens
        delivered = IERC20(option).balanceOf(address(this)) - optBefore;
        IERC20(option).safeTransfer(buyer, delivered);

        // Bookkeeping: track committed via Redemption token delta (fee-adjusted)
        address redemption = IOption(option).redemption();
        uint256 newRedBalance = IERC20(redemption).balanceOf(address(this));
        uint256 redMinted = newRedBalance - trackedRedemptionBalance[option];
        committed[option] += redMinted;
        totalCommitted += redMinted;
        trackedRedemptionBalance[option] = newRedBalance;

        emit MintAndDeliver(option, buyer, amount, delivered);
    }

    // ============ HOOK INTERACTION: PAIR REDEEM ============

    /// @inheritdoc IStrategyVault
    function pairRedeem(address option, uint256 amount) external override onlyHook nonReentrant whenNotPaused {
        if (!whitelistedOptions[option]) revert NotWhitelisted();
        if (amount == 0) revert ZeroAmount();

        address redemption = IOption(option).redemption();
        uint256 redBefore = IERC20(redemption).balanceOf(address(this));

        IOption(option).redeem(amount);

        uint256 redAfter = IERC20(redemption).balanceOf(address(this));
        uint256 redeemed = redBefore - redAfter;
        committed[option] -= redeemed;
        totalCommitted -= redeemed;
        trackedRedemptionBalance[option] = redAfter;

        emit PairRedeemed(option, amount);
    }

    // ============ HOOK INTERACTION: TRANSFER CASH ============

    /// @inheritdoc IStrategyVault
    function transferCash(address token, uint256 amount, address to) external override onlyHook nonReentrant {
        if (amount == 0) revert ZeroAmount();
        uint256 balance = IERC20(token).balanceOf(address(this));
        if (balance < amount) revert InsufficientCash();
        IERC20(token).safeTransfer(to, amount);
    }

    // ============ SETTLEMENT ============

    /// @inheritdoc IStrategyVault
    function handleSettlement(address option) external override nonReentrant {
        if (!whitelistedOptions[option]) revert NotWhitelisted();

        address redemption = IOption(option).redemption();
        uint256 previous = trackedRedemptionBalance[option];
        uint256 current = IERC20(redemption).balanceOf(address(this));

        uint256 settled = previous - current;
        if (settled == 0) revert NothingToSettle();

        committed[option] -= settled;
        totalCommitted -= settled;
        trackedRedemptionBalance[option] = current;

        emit SettlementReconciled(option, settled);
    }

    // ============ STRATEGY: ROLLING ============

    /// @inheritdoc IStrategyVault
    function rollOptions(address expiredOption) external override nonReentrant returns (address[] memory newOptions) {
        if (!whitelistedOptions[expiredOption]) revert NotWhitelisted();
        if (block.timestamp < IOption(expiredOption).expirationDate()) revert OptionNotExpired();
        if (rolled[expiredOption]) revert AlreadyRolled();
        if (strikeConfigs.length == 0) revert NoStrategyConfigured();

        rolled[expiredOption] = true;

        uint256 spot = getCollateralPrice();
        address collateral_ = asset();
        newOptions = new address[](strikeConfigs.length);

        for (uint256 i = 0; i < strikeConfigs.length; i++) {
            StrikeConfig memory cfg = strikeConfigs[i];

            // Compute strike from spot + offset
            uint96 newStrike = uint96(Math.mulDiv(spot, uint256(cfg.strikeOffsetBps), 10000));
            uint40 newExpiry = uint40(block.timestamp + uint256(cfg.duration));

            // Create option via factory
            address newOption = factory.createOption(collateral_, cashToken, newExpiry, newStrike, cfg.isPut);

            // Auto-whitelist
            whitelistedOptions[newOption] = true;
            newOptions[i] = newOption;

            emit OptionWhitelisted(newOption, true);
        }

        // Pay bounty to caller
        if (rollBounty > 0) {
            uint256 idle = IERC20(asset()).balanceOf(address(this));
            uint256 bounty = rollBounty > idle ? idle : rollBounty;
            if (bounty > 0) {
                IERC20(asset()).safeTransfer(msg.sender, bounty);
            }
        }

        emit OptionsRolled(expiredOption, newOptions, msg.sender, rollBounty);
    }

    // ============ PREMIUM MANAGEMENT ============

    /// @notice Swap accumulated cash tokens to collateral via external DEX
    /// @dev Only callable by owner. Verifies collateral increased. Resets approval after.
    function swapToCollateral(address considerationToken, address router, bytes calldata swapData)
        external
        onlyOwner
        nonReentrant
    {
        uint256 consBalance = IERC20(considerationToken).balanceOf(address(this));
        if (consBalance == 0) revert NoConsiderationToSwap();

        IERC20(considerationToken).forceApprove(router, consBalance);

        uint256 collBefore = IERC20(asset()).balanceOf(address(this));

        (bool success,) = router.call(swapData);
        if (!success) revert SwapFailed();

        // Reset approval
        IERC20(considerationToken).forceApprove(router, 0);

        uint256 collGained = IERC20(asset()).balanceOf(address(this)) - collBefore;
        if (collGained == 0) revert NoGainFromSwap();

        uint256 consSpent = consBalance - IERC20(considerationToken).balanceOf(address(this));
        totalPremiumsCollected += collGained;

        emit ConsiderationSwapped(considerationToken, consSpent, collGained);
    }

    // ============ ADMIN ============

    /// @notice Setup factory approvals so the vault can mint options
    /// @dev Must be called after deployment by owner
    function setupFactoryApproval() external onlyOwner {
        IERC20(asset()).forceApprove(address(factory), type(uint256).max);
        factory.approve(asset(), type(uint256).max);
    }

    function addHook(address hook_) external onlyOwner {
        if (hook_ == address(0)) revert InvalidAddress();
        authorizedHooks[hook_] = true;
        emit HookUpdated(hook_, true);
    }

    function removeHook(address hook_) external onlyOwner {
        authorizedHooks[hook_] = false;
        emit HookUpdated(hook_, false);
    }

    function whitelistOption(address option, bool allowed) external onlyOwner {
        whitelistedOptions[option] = allowed;
        emit OptionWhitelisted(option, allowed);
    }

    function setMaxCommitmentBps(uint256 bps) external onlyOwner {
        if (bps > 10000) revert InvalidBps();
        uint256 old = maxCommitmentBps;
        maxCommitmentBps = bps;
        emit MaxCommitmentUpdated(old, bps);
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
        if (bps > 5000) revert InvalidBps(); // max 50% spread
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

    function setRollBounty(uint256 bounty) external onlyOwner {
        uint256 old = rollBounty;
        rollBounty = bounty;
        emit RollBountyUpdated(old, bounty);
    }

    function setStrategy(StrikeConfig[] calldata configs) external onlyOwner {
        delete strikeConfigs;
        for (uint256 i = 0; i < configs.length; i++) {
            strikeConfigs.push(configs[i]);
        }
        emit StrategyUpdated();
    }

    /// @notice Manually create an option via factory
    function createOption(uint96 strike, uint40 expiration, bool isPut) external onlyOwner returns (address) {
        address opt = factory.createOption(asset(), cashToken, expiration, strike, isPut);
        whitelistedOptions[opt] = true;
        emit OptionWhitelisted(opt, true);
        return opt;
    }

    function setBlackScholes(address bs) external onlyOwner {
        if (bs == address(0)) revert InvalidAddress();
        blackScholes = IBlackScholes(bs);
    }

    function setPricePool(address pool) external onlyOwner {
        if (pool == address(0)) revert InvalidAddress();
        pricePool = IUniswapV3PoolOracle(pool);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    // ============ VIEW ============

    function idleCollateral() external view override returns (uint256) {
        return IERC20(asset()).balanceOf(address(this));
    }

    function utilizationBps() external view override returns (uint256) {
        uint256 total = totalAssets();
        if (total == 0) return 0;
        return (totalCommitted * 10000) / total;
    }

    function getVaultStats()
        external
        view
        override
        returns (
            uint256 totalAssets_,
            uint256 totalShares_,
            uint256 idle_,
            uint256 committed_,
            uint256 utilizationBps_,
            uint256 totalPremiums_
        )
    {
        totalAssets_ = totalAssets();
        totalShares_ = totalSupply();
        idle_ = IERC20(asset()).balanceOf(address(this));
        committed_ = totalCommitted;
        utilizationBps_ = totalAssets_ > 0 ? (totalCommitted * 10000) / totalAssets_ : 0;
        totalPremiums_ = totalPremiumsCollected;
    }

    function getPositionInfo(address option)
        external
        view
        override
        returns (uint256 committed_, uint256 redemptionBalance_, bool expired_)
    {
        committed_ = committed[option];
        address redemption = IOption(option).redemption();
        redemptionBalance_ = IERC20(redemption).balanceOf(address(this));
        expired_ = block.timestamp >= IOption(option).expirationDate();
    }

    function getStrikeConfigs() external view returns (StrikeConfig[] memory) {
        return strikeConfigs;
    }
}
