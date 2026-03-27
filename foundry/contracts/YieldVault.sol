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
import { ERC165 } from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import { IERC1271 } from "@openzeppelin/contracts/interfaces/IERC1271.sol";
import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

import { TickMath } from "@uniswap/v4-core/src/libraries/TickMath.sol";

import { IOption } from "./interfaces/IOption.sol";
import { IOptionFactory } from "./interfaces/IOptionFactory.sol";
import { IYieldVault } from "./interfaces/IYieldVault.sol";
import { IERC7540Redeem, IERC7540Operator } from "./interfaces/IERC7540.sol";

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

/// @title YieldVault
/// @notice ERC4626 vault that writes covered options with integrated pricing and strategy.
/// @dev Combines LP deposits, Black-Scholes pricing (via external contract), and option lifecycle.
///      Depositors provide collateral (e.g. WETH) and earn yield from option premiums.
///      The hook sells options → vault mints & delivers → options expire → settlement returns collateral.
///      Extends ERC4626 with ERC-7540 async redeems and EIP-1271 contract signatures for Bebop settlement.
contract YieldVault is ERC4626, ERC165, Ownable, ReentrancyGuardTransient, Pausable, IYieldVault, IERC7540Redeem, IERC7540Operator, IERC1271 {
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

    // ============ BEBOP INTEGRATION ============

    address public bebopApprovalTarget;

    // ============ COMMITMENT CAP ============

    uint256 public maxCommitmentBps;

    // ============ BOOKKEEPING ============

    address[] public activeOptions;
    mapping(address => bool) public override whitelistedOptions;
    uint256 public totalPremiumsCollected;

    // ============ ERC-7540: ASYNC REDEEM ============

    mapping(address => uint256) private _pendingRedeemShares;
    mapping(address => uint256) private _claimableRedeemShares;
    mapping(address => uint256) private _claimableRedeemAssets;
    uint256 private _totalPendingShares;
    uint256 private _totalClaimableShares;
    uint256 private _totalClaimableAssets;

    // ============ ERC-7540: OPERATORS ============

    mapping(address => mapping(address => bool)) private _operators;

    // ============ MODIFIERS ============

    modifier onlyHook() {
        if (!authorizedHooks[msg.sender]) revert OnlyHook();
        _;
    }

    modifier onlyOperatorOrOwner() {
        if (msg.sender != owner() && !_operators[owner()][msg.sender]) revert Unauthorized();
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

    /// @notice Total collateral committed across all active options (computed from redemption balances)
    function totalCommitted() public view override returns (uint256 total) {
        for (uint256 i = 0; i < activeOptions.length; i++) {
            total += IERC20(IOption(activeOptions[i]).redemption()).balanceOf(address(this));
        }
    }

    /// @notice Collateral committed to a specific option
    function committed(address option) public view override returns (uint256) {
        return IERC20(IOption(option).redemption()).balanceOf(address(this));
    }

    /// @notice Total assets actively backing shares (excludes assets earmarked for claimable redeems)
    function totalAssets() public view override returns (uint256) {
        return IERC20(asset()).balanceOf(address(this)) + totalCommitted() - _totalClaimableAssets;
    }

    /// @dev Active supply excludes claimable shares (locked in vault, awaiting claim)
    function _activeSupply() internal view returns (uint256) {
        return totalSupply() - _totalClaimableShares;
    }

    function _convertToShares(uint256 assets, Math.Rounding rounding) internal view override returns (uint256) {
        return assets.mulDiv(_activeSupply() + 10 ** _decimalsOffset(), totalAssets() + 1, rounding);
    }

    function _convertToAssets(uint256 shares, Math.Rounding rounding) internal view override returns (uint256) {
        return shares.mulDiv(totalAssets() + 1, _activeSupply() + 10 ** _decimalsOffset(), rounding);
    }

    /// @dev Sync deposits remain available. maxDeposit is uncapped (minus paused check).
    function maxDeposit(address) public view override returns (uint256) {
        return paused() ? 0 : type(uint256).max;
    }

    function maxMint(address) public view override returns (uint256) {
        return paused() ? 0 : type(uint256).max;
    }

    /// @notice Withdraw is disabled per ERC-7540 — use requestRedeem + redeem instead
    function maxWithdraw(address) public pure override returns (uint256) {
        return 0;
    }

    /// @notice Returns claimable shares (fulfilled redeem requests ready to claim)
    function maxRedeem(address controller) public view override returns (uint256) {
        return _claimableRedeemShares[controller];
    }

    /// @dev Preview functions revert for async redeems per ERC-7540
    function previewRedeem(uint256) public pure override returns (uint256) {
        revert AsyncOnly();
    }

    function previewWithdraw(uint256) public pure override returns (uint256) {
        revert AsyncOnly();
    }

    /// @notice Disabled — use requestRedeem + redeem
    function withdraw(uint256, address, address) public pure override returns (uint256) {
        revert WithdrawDisabled();
    }

    /// @notice Claim assets from a fulfilled redeem request (ERC-7540 claim function)
    /// @param shares Number of claimable shares to claim
    /// @param receiver Address to receive the assets
    /// @param controller Address that controls the claim (was `owner` in ERC-4626)
    function redeem(uint256 shares, address receiver, address controller)
        public
        override
        nonReentrant
        returns (uint256 assets)
    {
        if (msg.sender != controller && !_operators[controller][msg.sender]) revert Unauthorized();
        if (shares == 0) revert ZeroAmount();

        uint256 claimableShares = _claimableRedeemShares[controller];
        if (claimableShares < shares) revert InsufficientClaimable();

        // Pro-rata assets for partial claims
        assets = Math.mulDiv(_claimableRedeemAssets[controller], shares, claimableShares, Math.Rounding.Floor);

        _claimableRedeemShares[controller] -= shares;
        _claimableRedeemAssets[controller] -= assets;
        _totalClaimableShares -= shares;
        _totalClaimableAssets -= assets;

        _burn(address(this), shares);
        IERC20(asset()).safeTransfer(receiver, assets);

        emit Withdraw(msg.sender, receiver, controller, assets, shares);
    }

    // ============ ERC-7540: ASYNC REDEEM ============

    /// @inheritdoc IERC7540Redeem
    function requestRedeem(uint256 shares, address controller, address owner)
        external
        override
        nonReentrant
        returns (uint256)
    {
        if (msg.sender != owner && !_operators[owner][msg.sender]) revert Unauthorized();
        if (shares == 0) revert ZeroAmount();

        _transfer(owner, address(this), shares);
        _pendingRedeemShares[controller] += shares;
        _totalPendingShares += shares;

        emit RedeemRequest(controller, owner, 0, msg.sender, shares);
        return 0;
    }

    /// @inheritdoc IYieldVault
    function fulfillRedeem(address controller) public override onlyOwner nonReentrant {
        uint256 shares = _pendingRedeemShares[controller];
        if (shares == 0) revert ZeroAmount();

        uint256 assets = _convertToAssets(shares, Math.Rounding.Floor);
        uint256 availableIdle = IERC20(asset()).balanceOf(address(this)) - _totalClaimableAssets;
        if (availableIdle < assets) revert InsufficientIdle();

        _pendingRedeemShares[controller] = 0;
        _totalPendingShares -= shares;

        _claimableRedeemShares[controller] += shares;
        _claimableRedeemAssets[controller] += assets;
        _totalClaimableShares += shares;
        _totalClaimableAssets += assets;
    }

    /// @inheritdoc IYieldVault
    function fulfillRedeems(address[] calldata controllers) external override onlyOwner {
        for (uint256 i = 0; i < controllers.length; i++) {
            fulfillRedeem(controllers[i]);
        }
    }

    /// @inheritdoc IERC7540Redeem
    function pendingRedeemRequest(uint256, address controller) external view override returns (uint256) {
        return _pendingRedeemShares[controller];
    }

    /// @inheritdoc IERC7540Redeem
    function claimableRedeemRequest(uint256, address controller) external view override returns (uint256) {
        return _claimableRedeemShares[controller];
    }

    // ============ ERC-7540: OPERATORS ============

    /// @inheritdoc IERC7540Operator
    function setOperator(address operator, bool approved) external override returns (bool) {
        if (operator == msg.sender) revert InvalidAddress();
        _operators[msg.sender][operator] = approved;
        emit OperatorSet(msg.sender, operator, approved);
        return true;
    }

    /// @inheritdoc IERC7540Operator
    function isOperator(address controller, address operator) external view override returns (bool) {
        return _operators[controller][operator];
    }

    // ============ ERC-165 ============

    function supportsInterface(bytes4 interfaceId) public view override returns (bool) {
        return interfaceId == type(IERC7540Redeem).interfaceId || interfaceId == type(IERC7540Operator).interfaceId
            || interfaceId == type(IERC1271).interfaceId || super.supportsInterface(interfaceId);
    }

    // ============ OPERATOR ============

    /// @inheritdoc IYieldVault
    function burn(address option, uint256 amount) external override onlyOperatorOrOwner nonReentrant {
        if (!whitelistedOptions[option]) revert NotWhitelisted();
        if (amount == 0) revert ZeroAmount();
        IOption(option).redeem(amount);
        emit OptionsBurned(option, amount);
    }

    /// @notice Enable auto-mint/redeem on the factory for this vault
    function enableAutoMintRedeem(bool enabled) external onlyOwner {
        factory.enableAutoMintRedeem(enabled);
    }

    function _activateOption(address option) internal {
        if (!whitelistedOptions[option]) {
            whitelistedOptions[option] = true;
            activeOptions.push(option);
        }
    }

    // ============ EIP-1271: CONTRACT SIGNATURE VALIDATION ============

    /// @notice Validates signatures for Bebop settlement — allows authorized operators to sign on behalf of vault
    /// @inheritdoc IERC1271
    function isValidSignature(bytes32 hash, bytes calldata signature) external view override returns (bytes4) {
        address signer = ECDSA.recover(hash, signature);
        if (signer == owner() || _operators[owner()][signer]) {
            return 0x1626ba7e; // IERC1271.isValidSignature.selector
        }
        return 0xffffffff;
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

        uint256 sqrtPriceX32 = uint256(sqrtPriceX96) >> 64;
        uint256 priceX64 = sqrtPriceX32 * sqrtPriceX32;
        price_ = (priceX64 * 1e18) >> 64;

        uint8 decimals0 = IERC20Metadata(pricePool.token0()).decimals();
        uint8 decimals1 = IERC20Metadata(pricePool.token1()).decimals();
        if (decimals1 > decimals0) {
            price_ = price_ / (10 ** (decimals1 - decimals0));
        } else if (decimals0 > decimals1) {
            price_ = price_ * (10 ** (decimals0 - decimals1));
        }

        bool collateralIsToken1 = pricePool.token1() == asset();
        if (collateralIsToken1) {
            require(price_ > 0, "Price cannot be zero for inverse");
            price_ = 1e36 / price_;
        }
    }

    /// @inheritdoc IYieldVault
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

        uint256 halfSpread = spreadBps / 2;
        uint256 bsPrice;
        if (cashForOption) {
            bsPrice = Math.mulDiv(midPrice, 10000 + halfSpread, 10000);
        } else {
            bsPrice = Math.mulDiv(midPrice, 10000 - halfSpread, 10000);
        }

        uint256 scaleFactor = 10 ** (36 - uint256(_cashDecimals));

        if (cashForOption) {
            outputAmount = Math.mulDiv(amount, scaleFactor, bsPrice);
        } else {
            outputAmount = Math.mulDiv(amount, bsPrice, scaleFactor);
        }

        unitPrice = Math.mulDiv(bsPrice, 10 ** uint256(_cashDecimals), 1e18);
    }

    // ============ HOOK INTERACTION: MINT AND DELIVER ============

    /// @inheritdoc IYieldVault
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

        uint256 total = totalAssets();
        if (totalCommitted() + amount > (total * maxCommitmentBps) / 10000) revert ExceedsCommitmentCap();

        uint256 idle = IERC20(asset()).balanceOf(address(this)) - _totalClaimableAssets;
        if (amount > idle) revert InsufficientIdle();

        uint256 optBefore = IERC20(option).balanceOf(address(this));

        IOption(option).mint(address(this), amount);

        delivered = IERC20(option).balanceOf(address(this)) - optBefore;
        IERC20(option).safeTransfer(buyer, delivered);

        emit MintAndDeliver(option, buyer, amount, delivered);
    }

    // ============ HOOK INTERACTION: PAIR REDEEM ============

    /// @inheritdoc IYieldVault
    function pairRedeem(address option, uint256 amount) external override onlyHook nonReentrant whenNotPaused {
        if (!whitelistedOptions[option]) revert NotWhitelisted();
        if (amount == 0) revert ZeroAmount();
        IOption(option).redeem(amount);
        emit PairRedeemed(option, amount);
    }

    // ============ HOOK INTERACTION: TRANSFER CASH ============

    /// @inheritdoc IYieldVault
    function transferCash(address token, uint256 amount, address to) external override onlyHook nonReentrant {
        if (amount == 0) revert ZeroAmount();
        uint256 balance = IERC20(token).balanceOf(address(this));
        if (balance < amount) revert InsufficientCash();
        IERC20(token).safeTransfer(to, amount);
    }

    // ============ SETTLEMENT ============

    /// @inheritdoc IYieldVault
    /// @dev With live commitment tracking, this is just a no-op event emitter for off-chain indexing.
    function handleSettlement(address option) external override nonReentrant {
        if (!whitelistedOptions[option]) revert NotWhitelisted();
        emit SettlementReconciled(option, committed(option));
    }

    // ============ STRATEGY: ROLLING ============

    /// @inheritdoc IYieldVault
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

            uint96 newStrike = uint96(Math.mulDiv(spot, uint256(cfg.strikeOffsetBps), 10000));
            uint40 newExpiry = uint40(block.timestamp + uint256(cfg.duration));

            address newOption = factory.createOption(collateral_, cashToken, newExpiry, newStrike, cfg.isPut);

            _activateOption(newOption);
            newOptions[i] = newOption;

            emit OptionWhitelisted(newOption, true);
        }

        if (rollBounty > 0) {
            uint256 idle = IERC20(asset()).balanceOf(address(this)) - _totalClaimableAssets;
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
        if (allowed) {
            _activateOption(option); // pushes to activeOptions + sets whitelistedOptions
        } else {
            whitelistedOptions[option] = false;
        }
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
        _activateOption(opt);
        emit OptionWhitelisted(opt, true);
        return opt;
    }

    function setBebopApprovalTarget(address target) external override onlyOwner {
        bebopApprovalTarget = target;
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
        return IERC20(asset()).balanceOf(address(this)) - _totalClaimableAssets;
    }

    function utilizationBps() external view override returns (uint256) {
        uint256 total = totalAssets();
        if (total == 0) return 0;
        return (totalCommitted() * 10000) / total;
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
        totalShares_ = _activeSupply();
        idle_ = IERC20(asset()).balanceOf(address(this)) - _totalClaimableAssets;
        committed_ = totalCommitted();
        utilizationBps_ = totalAssets_ > 0 ? (committed_ * 10000) / totalAssets_ : 0;
        totalPremiums_ = totalPremiumsCollected;
    }

    function getPositionInfo(address option)
        external
        view
        override
        returns (uint256 committed_, uint256 redemptionBalance_, bool expired_)
    {
        address redemption = IOption(option).redemption();
        committed_ = IERC20(redemption).balanceOf(address(this));
        redemptionBalance_ = committed_;
        expired_ = block.timestamp >= IOption(option).expirationDate();
    }

    function getStrikeConfigs() external view returns (StrikeConfig[] memory) {
        return strikeConfigs;
    }
}
