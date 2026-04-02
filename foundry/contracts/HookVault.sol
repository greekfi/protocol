// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

import { ERC4626 } from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { ReentrancyGuardTransient } from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

import { TickMath } from "@uniswap/v4-core/src/libraries/TickMath.sol";
import { IUniswapV3Pool } from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import { IUniswapV3SwapCallback } from "@uniswap/v3-core/contracts/interfaces/callback/IUniswapV3SwapCallback.sol";

import { IOption } from "./interfaces/IOption.sol";
import { IOptionFactory } from "./interfaces/IOptionFactory.sol";

using SafeERC20 for IERC20;

interface IOptionPricer {
    function price(address option, uint256 amount, bool isBuy, int256 netInventory, uint256 totalAssets)
        external
        view
        returns (uint256 outputAmount, uint256 unitPrice);
    function getCollateralPrice() external view returns (uint256);
}

/// @title HookVault
/// @notice ERC4626 vault with integrated pricing and strategy for the Uniswap v4 hook.
/// @dev Depositors provide collateral (e.g. WETH) and earn yield from option premiums.
///      Hook sells/buys options via auto-mint/redeem. Cash auto-swapped via Uniswap v3.
///      Inventory-based spread: wider ask when vault is more short, tighter bid to encourage buyback.
contract HookVault is ERC4626, Ownable, ReentrancyGuardTransient, Pausable, IUniswapV3SwapCallback {
    using Math for uint256;

    // ============ STRUCTS ============

    struct StrikeConfig {
        uint16 strikeOffsetBps;
        bool isPut;
        uint40 duration;
    }

    // ============ ERRORS ============

    error OnlyHookOrOwner();
    error NotWhitelisted();
    error ExceedsCommitmentCap();
    error InsufficientIdle();
    error NothingToSettle();
    error InvalidAddress();
    error InvalidBps();
    error InvalidCallback();
    error ZeroAmount();
    error OptionNotExpired();
    error AlreadyRolled();
    error CollateralMismatch();
    error NoStrategyConfigured();

    // ============ EVENTS ============

    event OptionsSold(address indexed option, address indexed buyer, uint256 amount, uint256 committed);
    event OptionsBoughtBack(address indexed option, uint256 amount, uint256 freed);
    event Swapped(address indexed tokenIn, address indexed tokenOut, uint256 amountIn, uint256 amountOut);
    event SettlementReconciled(address indexed option, uint256 settled);
    event HookUpdated(address indexed hook, bool authorized);
    event OptionWhitelisted(address indexed option, bool allowed);
    event MaxCommitmentUpdated(uint256 oldBps, uint256 newBps);
    event OptionsRolled(address indexed expiredOption, address[] newOptions, address indexed caller, uint256 bounty);
    event StrategyUpdated();
    event RollBountyUpdated(uint256 oldBounty, uint256 newBounty);
    event SwapPoolUpdated(address indexed cashToken, address pool);
    event PricerUpdated(address oldPricer, address newPricer);

    // ============ PRICING ============

    IOptionPricer public pricer;

    // ============ STRATEGY ============

    IOptionFactory public factory;
    StrikeConfig[] public strikeConfigs;
    uint256 public rollBounty;
    mapping(address => bool) public rolled;

    // ============ HOOKS ============

    mapping(address => bool) public authorizedHooks;

    // ============ COMMITMENT CAP ============

    uint256 public maxCommitmentBps;

    // ============ BOOKKEEPING ============

    uint256 public totalCommitted;
    mapping(address => uint256) public committed;
    mapping(address => uint256) public trackedRedemptionBalance;
    mapping(address => bool) public whitelistedOptions;
    uint256 public totalPremiumsCollected;

    // ============ INVENTORY ============

    int256 public netInventory;

    // ============ SWAP ============

    mapping(address => IUniswapV3Pool) public swapPools; // cashToken → v3 pool

    // ============ MODIFIERS ============

    modifier onlyHook() {
        if (!authorizedHooks[msg.sender]) revert OnlyHookOrOwner();
        _;
    }

    modifier onlyHookOrOwner() {
        if (!authorizedHooks[msg.sender] && msg.sender != owner()) revert OnlyHookOrOwner();
        _;
    }

    // ============ CONSTRUCTOR ============

    constructor(
        IERC20 collateral_,
        string memory name_,
        string memory symbol_,
        address factory_,
        address pricer_
    ) ERC4626(collateral_) ERC20(name_, symbol_) Ownable(msg.sender) {
        if (factory_ == address(0) || pricer_ == address(0)) revert InvalidAddress();
        factory = IOptionFactory(factory_);
        pricer = IOptionPricer(pricer_);
        maxCommitmentBps = 8000;
    }

    // ============ ERC4626 OVERRIDES ============

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

    function price(address option, uint256 amount, bool isBuy)
        external
        view
        returns (uint256 outputAmount, uint256 unitPrice)
    {
        return pricer.price(option, amount, isBuy, netInventory, totalAssets());
    }

    // ============ HOOK INTERACTION ============

    /// @notice Sell options: auto-mint via transferFrom, track commitment + inventory
    /// @param option Option address (must be whitelisted)
    /// @param to Recipient of options
    /// @param amount Number of option tokens to deliver (18 decimals)
    function sellOptions(address option, address to, uint256 amount) external onlyHook nonReentrant whenNotPaused {
        if (!whitelistedOptions[option]) revert NotWhitelisted();
        if (amount == 0) revert ZeroAmount();
        if (IOption(option).collateral() != asset()) revert CollateralMismatch();

        uint256 total = totalAssets();
        if (totalCommitted + amount > (total * maxCommitmentBps) / 10000) revert ExceedsCommitmentCap();

        address redemption = IOption(option).redemption();
        uint256 redBefore = IERC20(redemption).balanceOf(address(this));

        // transferFrom triggers auto-mint: vault's collateral → Redemption, options minted to `to`
        IOption(option).transferFrom(address(this), to, amount);

        uint256 redAfter = IERC20(redemption).balanceOf(address(this));
        uint256 redMinted = redAfter - redBefore;
        committed[option] += redMinted;
        totalCommitted += redMinted;
        trackedRedemptionBalance[option] = redAfter;

        netInventory += int256(amount);

        emit OptionsSold(option, to, amount, redMinted);
    }

    /// @notice Record a buyback after options arrived at vault (auto-redeem already fired)
    /// @param option Option address
    /// @param amount Number of options that were bought back
    function recordBuyback(address option, uint256 amount) external onlyHook nonReentrant {
        if (!whitelistedOptions[option]) revert NotWhitelisted();

        address redemption = IOption(option).redemption();
        uint256 redBefore = trackedRedemptionBalance[option];
        uint256 redAfter = IERC20(redemption).balanceOf(address(this));

        if (redAfter < redBefore) {
            uint256 redeemed = redBefore - redAfter;
            committed[option] -= redeemed;
            totalCommitted -= redeemed;
        }
        trackedRedemptionBalance[option] = redAfter;

        netInventory -= int256(amount);

        emit OptionsBoughtBack(option, amount, redBefore > redAfter ? redBefore - redAfter : 0);
    }

    // ============ SWAP (Uniswap v3) ============

    /// @notice Swap between a cash token and collateral via Uniswap v3
    /// @param cashToken_ The cash token to swap (e.g. USDC, USDT)
    /// @param cashToCollateral true = swap cash→collateral, false = swap collateral→cash
    /// @param amount Input amount (0 = swap all cash when cashToCollateral)
    function swap(address cashToken_, bool cashToCollateral, uint256 amount)
        external
        onlyHookOrOwner
        nonReentrant
        returns (uint256 amountOut)
    {
        address tokenIn = cashToCollateral ? cashToken_ : asset();
        address tokenOut = cashToCollateral ? asset() : cashToken_;

        if (amount == 0) {
            if (!cashToCollateral) revert ZeroAmount();
            amount = IERC20(tokenIn).balanceOf(address(this));
        }
        if (amount == 0) return 0;

        IUniswapV3Pool pool = swapPools[cashToken_];
        require(address(pool) != address(0), "No swap pool for token");

        bool zeroForOne = tokenIn < tokenOut;
        uint160 sqrtPriceLimitX96 = zeroForOne
            ? TickMath.getSqrtPriceAtTick(TickMath.MIN_TICK + 1)
            : TickMath.getSqrtPriceAtTick(TickMath.MAX_TICK - 1);

        uint256 balBefore = IERC20(tokenOut).balanceOf(address(this));

        pool.swap(address(this), zeroForOne, int256(amount), sqrtPriceLimitX96, abi.encode(tokenIn));

        amountOut = IERC20(tokenOut).balanceOf(address(this)) - balBefore;

        if (cashToCollateral) {
            totalPremiumsCollected += amountOut;
        }

        emit Swapped(tokenIn, tokenOut, amount, amountOut);
    }

    /// @inheritdoc IUniswapV3SwapCallback
    function uniswapV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata data) external {
        if (!_isSwapPool(msg.sender)) revert InvalidCallback();
        address tokenIn = abi.decode(data, (address));
        uint256 amountToPay = amount0Delta > 0 ? uint256(amount0Delta) : uint256(amount1Delta);
        IERC20(tokenIn).safeTransfer(msg.sender, amountToPay);
    }

    function _isSwapPool(address caller) internal view returns (bool) {
        // Check all registered swap pools
        return caller == address(swapPools[IUniswapV3Pool(caller).token0()])
            || caller == address(swapPools[IUniswapV3Pool(caller).token1()]);
    }

    // ============ SETTLEMENT ============

    function handleSettlement(address option) external nonReentrant {
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

    function rollOptions(address expiredOption) external nonReentrant returns (address[] memory newOptions) {
        if (!whitelistedOptions[expiredOption]) revert NotWhitelisted();
        if (block.timestamp < IOption(expiredOption).expirationDate()) revert OptionNotExpired();
        if (rolled[expiredOption]) revert AlreadyRolled();
        if (strikeConfigs.length == 0) revert NoStrategyConfigured();

        rolled[expiredOption] = true;

        uint256 spot = pricer.getCollateralPrice();
        address collateral_ = asset();
        newOptions = new address[](strikeConfigs.length);

        for (uint256 i = 0; i < strikeConfigs.length; i++) {
            StrikeConfig memory cfg = strikeConfigs[i];
            uint96 newStrike = uint96(Math.mulDiv(spot, uint256(cfg.strikeOffsetBps), 10000));
            uint40 newExpiry = uint40(block.timestamp + uint256(cfg.duration));
            address newOption = factory.createOption(
                collateral_, IOption(expiredOption).consideration(), newExpiry, newStrike, cfg.isPut
            );
            whitelistedOptions[newOption] = true;
            newOptions[i] = newOption;
            emit OptionWhitelisted(newOption, true);
        }

        if (rollBounty > 0) {
            uint256 idle = IERC20(asset()).balanceOf(address(this));
            uint256 bounty = rollBounty > idle ? idle : rollBounty;
            if (bounty > 0) {
                IERC20(asset()).safeTransfer(msg.sender, bounty);
            }
        }

        emit OptionsRolled(expiredOption, newOptions, msg.sender, rollBounty);
    }

    // ============ ADMIN ============

    function setupFactoryApproval() external onlyOwner {
        IERC20(asset()).forceApprove(address(factory), type(uint256).max);
        factory.approve(asset(), type(uint256).max);
    }

    /// @notice Setup hook permissions: auto-mint + operator approval
    function setupHookApproval(address hook_) external onlyOwner {
        factory.enableAutoMintRedeem(true);
        factory.approveOperator(hook_, true);
    }

    /// @notice Approve a hook to pull a cash token from the vault (for buyback flow)
    function approveCashForHook(address cashToken_, address hook_) external onlyOwner {
        IERC20(cashToken_).forceApprove(hook_, type(uint256).max);
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

    function setPricer(address pricer_) external onlyOwner {
        if (pricer_ == address(0)) revert InvalidAddress();
        address old = address(pricer);
        pricer = IOptionPricer(pricer_);
        emit PricerUpdated(old, pricer_);
    }

    /// @notice Register a Uniswap v3 pool for swapping a cash token <> collateral
    function setSwapPool(address cashToken_, address pool) external onlyOwner {
        if (pool == address(0)) revert InvalidAddress();
        swapPools[cashToken_] = IUniswapV3Pool(pool);
        emit SwapPoolUpdated(cashToken_, pool);
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

    function createOption(address cashToken_, uint96 strike, uint40 expiration, bool isPut)
        external
        onlyOwner
        returns (address)
    {
        address opt = factory.createOption(asset(), cashToken_, expiration, strike, isPut);
        whitelistedOptions[opt] = true;
        emit OptionWhitelisted(opt, true);
        return opt;
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    // ============ VIEW ============

    function idleCollateral() external view returns (uint256) {
        return IERC20(asset()).balanceOf(address(this));
    }

    function utilizationBps() external view returns (uint256) {
        uint256 total = totalAssets();
        if (total == 0) return 0;
        return (totalCommitted * 10000) / total;
    }

    function getVaultStats()
        external
        view
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
