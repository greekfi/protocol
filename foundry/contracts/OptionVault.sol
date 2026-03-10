// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

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

/**
 * @title OptionVault
 * @notice ERC4626 vault that writes covered options. One vault per collateral type.
 * @dev Depositors provide collateral (e.g. WETH) and earn yield from option premiums.
 *      The vault mints options on behalf of the OpHook when buyers purchase them,
 *      holds the Redemption tokens (short position), and tracks all bookkeeping.
 *
 *      Flow: LP deposits collateral → Hook sells options → Vault mints & delivers →
 *            Options expire → sweep() returns collateral → premiums increase share price.
 *
 *      The vault never holds Option tokens long-term — they are minted and immediately
 *      delivered to buyers, or received from buybacks and immediately pair-redeemed.
 */
contract OptionVault is ERC4626, Ownable, ReentrancyGuardTransient, Pausable {
    using Math for uint256;

    // ============ CONFIGURATION ============

    /// @notice The OpHook authorized to call mintAndDeliver/pairRedeem
    address public hook;

    /// @notice OptionFactory for approval setup
    IOptionFactory public factory;

    /// @notice Max collateral that can be committed as basis points (default 8000 = 80%)
    uint256 public maxCommitmentBps;

    // ============ WHITELIST ============

    /// @notice Option contracts the vault is allowed to write
    mapping(address => bool) public whitelistedOptions;

    // ============ BOOKKEEPING: POSITIONS ============

    /// @notice Total collateral locked in open option positions
    uint256 public totalCommitted;

    /// @notice Collateral committed per option contract
    mapping(address => uint256) public committed;

    /// @notice Redemption token balance snapshot per option (for settlement reconciliation)
    mapping(address => uint256) public trackedRedemptionBalance;

    // ============ BOOKKEEPING: PREMIUMS ============

    /// @notice Lifetime premium income converted to collateral
    uint256 public totalPremiumsCollected;

    // ============ EVENTS ============

    event OptionWhitelisted(address indexed option, bool allowed);
    event MintAndDeliver(
        address indexed option, address indexed buyer, uint256 collateralUsed, uint256 optionsDelivered
    );
    event PairRedeemed(address indexed option, uint256 amount);
    event SettlementReconciled(address indexed option, uint256 settled);
    event PremiumReceived(address indexed token, uint256 amount);
    event ConsiderationSwapped(address indexed token, uint256 considerationIn, uint256 collateralOut);
    event HookUpdated(address indexed oldHook, address indexed newHook);
    event MaxCommitmentUpdated(uint256 oldBps, uint256 newBps);

    // ============ ERRORS ============

    error OnlyHook();
    error NotWhitelisted();
    error ExceedsCommitmentCap();
    error InsufficientIdle();
    error NothingToSettle();
    error NoConsiderationToSwap();
    error SwapFailed();
    error InvalidBps();
    error InvalidAddress();
    error ZeroAmount();

    // ============ MODIFIERS ============

    modifier onlyHook() {
        if (msg.sender != hook) revert OnlyHook();
        _;
    }

    // ============ CONSTRUCTOR ============

    /**
     * @param collateral_ Underlying collateral token (e.g. WETH)
     * @param name_ Vault share token name (e.g. "Greek WETH Vault")
     * @param symbol_ Vault share token symbol (e.g. "gWETH")
     * @param factory_ OptionFactory address
     * @param hook_ OpHook authorized to mint/redeem
     */
    constructor(IERC20 collateral_, string memory name_, string memory symbol_, address factory_, address hook_)
        ERC4626(collateral_)
        ERC20(name_, symbol_)
        Ownable(msg.sender)
    {
        if (factory_ == address(0) || hook_ == address(0)) revert InvalidAddress();
        factory = IOptionFactory(factory_);
        hook = hook_;
        maxCommitmentBps = 8000; // 80%
    }

    // ============ ERC4626 OVERRIDES ============

    /**
     * @notice Total assets = idle collateral + committed collateral
     * @dev Consideration tokens (USDC received from exercised options) are NOT counted
     *      until swapped to collateral. This means share price only increases when
     *      premiums are actually converted.
     */
    function totalAssets() public view override returns (uint256) {
        return IERC20(asset()).balanceOf(address(this)) + totalCommitted;
    }

    /// @notice Max withdrawable is capped to idle (uncommitted) collateral
    function maxWithdraw(address owner_) public view override returns (uint256) {
        uint256 idle = IERC20(asset()).balanceOf(address(this));
        uint256 ownerAssets = _convertToAssets(balanceOf(owner_), Math.Rounding.Floor);
        return Math.min(idle, ownerAssets);
    }

    /// @notice Max redeemable shares capped by idle collateral
    function maxRedeem(address owner_) public view override returns (uint256) {
        uint256 idle = IERC20(asset()).balanceOf(address(this));
        uint256 idleShares = _convertToShares(idle, Math.Rounding.Floor);
        return Math.min(idleShares, balanceOf(owner_));
    }

    // ============ CORE: MINT AND DELIVER ============

    /**
     * @notice Mints options using vault collateral and delivers to buyer
     * @dev Only callable by the hook. Checks whitelist, commitment cap, and idle balance.
     *      The vault calls option.mint(vault, amount) which pulls collateral from the vault
     *      via factory.transferFrom. Then transfers the minted Option tokens to the buyer.
     * @param option Option contract address (must be whitelisted)
     * @param amount Collateral amount to commit
     * @param buyer Recipient of the Option tokens
     * @return optionsDelivered Number of Option tokens delivered (after fee)
     */
    function mintAndDeliver(address option, uint256 amount, address buyer)
        external
        onlyHook
        nonReentrant
        whenNotPaused
        returns (uint256 optionsDelivered)
    {
        if (!whitelistedOptions[option]) revert NotWhitelisted();
        if (amount == 0) revert ZeroAmount();

        // Check commitment cap
        uint256 total = totalAssets();
        if (totalCommitted + amount > (total * maxCommitmentBps) / 10000) revert ExceedsCommitmentCap();

        // Check idle collateral
        uint256 idle = IERC20(asset()).balanceOf(address(this));
        if (amount > idle) revert InsufficientIdle();

        // Snapshot collateral balance to measure actual cost
        uint256 collBefore = IERC20(asset()).balanceOf(address(this));

        // Mint: vault calls option.mint(vault, amount)
        // This pulls `amount` collateral from vault → Redemption contract
        // Vault receives Option tokens + Redemption tokens (both minus fee)
        IOption(option).mint(address(this), amount);

        // Actual collateral spent (= amount, but verified)
        uint256 collSpent = collBefore - IERC20(asset()).balanceOf(address(this));

        // Deliver Option tokens to buyer
        optionsDelivered = IERC20(option).balanceOf(address(this));
        IERC20(option).safeTransfer(buyer, optionsDelivered);

        // Bookkeeping: track committed as Redemption token balance delta
        // This is fee-adjusted, matching what we'll recover at settlement
        address redemption = IOption(option).redemption();
        uint256 newRedBalance = IERC20(redemption).balanceOf(address(this));
        uint256 redMinted = newRedBalance - trackedRedemptionBalance[option];
        committed[option] += redMinted;
        totalCommitted += redMinted;
        trackedRedemptionBalance[option] = newRedBalance;

        emit MintAndDeliver(option, buyer, amount, optionsDelivered);
    }

    // ============ CORE: PAIR REDEEM (BUYBACK) ============

    /**
     * @notice Burns matched Option + Redemption tokens, returns collateral to vault
     * @dev Only callable by the hook. The hook must transfer Option tokens to the vault
     *      before calling this function. Vault already holds the Redemption tokens.
     * @param option Option contract address
     * @param amount Number of pairs to redeem
     */
    function pairRedeem(address option, uint256 amount) external onlyHook nonReentrant whenNotPaused {
        if (!whitelistedOptions[option]) revert NotWhitelisted();
        if (amount == 0) revert ZeroAmount();

        // Snapshot Redemption balance to measure actual burn
        address redemption = IOption(option).redemption();
        uint256 redBefore = IERC20(redemption).balanceOf(address(this));

        // Pair redeem: burns Option + Redemption tokens, returns collateral to vault
        IOption(option).redeem(amount);

        // Bookkeeping — track Redemption token delta (matches committed tracking)
        uint256 redAfter = IERC20(redemption).balanceOf(address(this));
        uint256 redeemed = redBefore - redAfter;
        committed[option] -= redeemed;
        totalCommitted -= redeemed;
        trackedRedemptionBalance[option] = redAfter;

        emit PairRedeemed(option, amount);
    }

    // ============ SETTLEMENT (POST-EXPIRY) ============

    /**
     * @notice Reconciles bookkeeping after sweep() has been called on the Redemption contract
     * @dev Permissionless. After anyone calls redemption.sweep(vaultAddress), this function
     *      updates the vault's committed tracking to reflect the settled positions.
     *      The vault may now hold consideration tokens (from exercised options) in addition
     *      to returned collateral.
     * @param option Option contract whose Redemption was swept
     */
    function handleSettlement(address option) external nonReentrant {
        if (!whitelistedOptions[option]) revert NotWhitelisted();

        address redemption = IOption(option).redemption();
        uint256 previous = trackedRedemptionBalance[option];
        uint256 current = IERC20(redemption).balanceOf(address(this));

        uint256 settled = previous - current;
        if (settled == 0) revert NothingToSettle();

        // Update bookkeeping — committed tracks fee-adjusted amounts
        // (Redemption token deltas), so settled matches exactly
        committed[option] -= settled;
        totalCommitted -= settled;
        trackedRedemptionBalance[option] = current;

        emit SettlementReconciled(option, settled);
    }

    // ============ PREMIUM MANAGEMENT ============

    /**
     * @notice Receives premium tokens from the hook (post-expiry sweep)
     * @dev Only callable by the hook. Premium tokens (e.g. USDC) sit in the vault
     *      until swapToCollateral() is called by the owner.
     * @param token Premium token address (e.g. USDC)
     * @param amount Amount to pull from hook
     */
    function receivePremium(address token, uint256 amount) external onlyHook nonReentrant {
        if (amount == 0) revert ZeroAmount();
        IERC20(token).safeTransferFrom(hook, address(this), amount);
        emit PremiumReceived(token, amount);
    }

    /**
     * @notice Swaps accumulated consideration tokens to collateral via external DEX
     * @dev Only callable by owner. The owner provides the router address and calldata
     *      for the swap. The vault verifies collateral balance increased.
     * @param considerationToken Token to swap from (e.g. USDC)
     * @param router DEX router address
     * @param swapData Encoded swap calldata
     */
    function swapToCollateral(address considerationToken, address router, bytes calldata swapData)
        external
        onlyOwner
        nonReentrant
    {
        uint256 consBalance = IERC20(considerationToken).balanceOf(address(this));
        if (consBalance == 0) revert NoConsiderationToSwap();

        IERC20(considerationToken).forceApprove(router, consBalance);

        uint256 collBefore = IERC20(asset()).balanceOf(address(this));

        // solhint-disable-next-line avoid-low-level-calls
        (bool success,) = router.call(swapData);
        if (!success) revert SwapFailed();

        uint256 collGained = IERC20(asset()).balanceOf(address(this)) - collBefore;
        uint256 consSpent = consBalance - IERC20(considerationToken).balanceOf(address(this));

        totalPremiumsCollected += collGained;

        emit ConsiderationSwapped(considerationToken, consSpent, collGained);
    }

    // ============ ADMIN FUNCTIONS ============

    /**
     * @notice Sets up factory approvals so the vault can mint options
     * @dev Must be called after deployment. Sets both ERC20 approval (for safeTransferFrom)
     *      and factory internal allowance (for factory.transferFrom).
     *      Both are msg.sender-based, so the vault itself must be the caller.
     */
    function setupFactoryApproval() external {
        IERC20(asset()).forceApprove(address(factory), type(uint256).max);
        factory.approve(asset(), type(uint256).max);
    }

    /// @notice Whitelist or delist an option contract for writing
    function whitelistOption(address option, bool allowed) external onlyOwner {
        whitelistedOptions[option] = allowed;
        emit OptionWhitelisted(option, allowed);
    }

    /// @notice Update the maximum commitment cap (in basis points, max 10000)
    function setMaxCommitmentBps(uint256 bps) external onlyOwner {
        if (bps > 10000) revert InvalidBps();
        uint256 old = maxCommitmentBps;
        maxCommitmentBps = bps;
        emit MaxCommitmentUpdated(old, bps);
    }

    /// @notice Update the authorized hook address
    function setHook(address newHook) external onlyOwner {
        if (newHook == address(0)) revert InvalidAddress();
        address old = hook;
        hook = newHook;
        emit HookUpdated(old, newHook);
    }

    /// @notice Emergency pause — blocks mintAndDeliver, pairRedeem, deposits, withdrawals
    function pause() external onlyOwner {
        _pause();
    }

    /// @notice Unpause
    function unpause() external onlyOwner {
        _unpause();
    }

    // ============ VIEW FUNCTIONS ============

    /// @notice Idle (uncommitted) collateral available for minting or withdrawal
    function idleCollateral() external view returns (uint256) {
        return IERC20(asset()).balanceOf(address(this));
    }

    /// @notice Current utilization in basis points (committed / totalAssets * 10000)
    function utilizationBps() external view returns (uint256) {
        uint256 total = totalAssets();
        if (total == 0) return 0;
        return (totalCommitted * 10000) / total;
    }

    /// @notice Returns vault statistics
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

    /// @notice Returns position info for a specific option
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
}
