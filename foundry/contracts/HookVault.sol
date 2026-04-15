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

interface ISwapRouter02 {
    struct ExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
    }

    function exactInputSingle(ExactInputSingleParams calldata params) external payable returns (uint256 amountOut);
}

/// @title HookVault
/// @notice ERC4626 vault with integrated pricing and strategy for the Uniswap v4 hook.
/// @dev Depositors provide collateral (e.g. WETH) and earn yield from option premiums.
///      Hook sells/buys options via auto-mint/redeem. Cash auto-swapped via Uniswap v3.
///      Inventory-based spread: wider ask when vault is more short, tighter bid to encourage buyback.
contract HookVault is ERC4626, Ownable, ReentrancyGuardTransient, Pausable {
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

    ISwapRouter02 public swapRouter;
    mapping(address => uint24) public swapFees; // cashToken → v3 pool fee tier

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

    constructor(IERC20 collateral_, string memory name_, string memory symbol_, address factory_, address pricer_)
        ERC4626(collateral_)
        ERC20(name_, symbol_)
        Ownable(msg.sender)
    {
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
        require(IOption(option).transferFrom(address(this), to, amount), "transferFrom failed");

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

    /// @notice Swap between a cash token and collateral via Uniswap v3 router
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

        uint24 fee = swapFees[cashToken_];
        require(fee > 0, "No swap fee for token");

        IERC20(tokenIn).forceApprove(address(swapRouter), amount);

        amountOut = swapRouter.exactInputSingle(
            ISwapRouter02.ExactInputSingleParams({
                tokenIn: tokenIn,
                tokenOut: tokenOut,
                fee: fee,
                recipient: address(this),
                amountIn: amount,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            })
        );

        if (cashToCollateral) {
            totalPremiumsCollected += amountOut;
        }

        emit Swapped(tokenIn, tokenOut, amount, amountOut);
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

    function setSwapRouter(address router) external onlyOwner {
        if (router == address(0)) revert InvalidAddress();
        swapRouter = ISwapRouter02(router);
    }

    /// @notice Register a v3 fee tier for swapping a cash token <> collateral
    function setSwapFee(address cashToken_, uint24 fee) external onlyOwner {
        swapFees[cashToken_] = fee;
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
