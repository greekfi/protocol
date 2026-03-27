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
import { ERC165 } from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import { IERC1271 } from "@openzeppelin/contracts/interfaces/IERC1271.sol";
import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

import { IOption } from "./interfaces/IOption.sol";
import { IOptionFactory } from "./interfaces/IOptionFactory.sol";
import { IERC7540Redeem, IERC7540Operator } from "./interfaces/IERC7540.sol";

using SafeERC20 for IERC20;

/// @title YieldVault
/// @notice ERC4626 vault for option collateral. Depositors provide collateral and earn yield from premiums.
/// @dev ERC-7540 async redeems (collateral may be locked in active options).
///      EIP-1271 contract signatures allow operators to act as Bebop taker on behalf of the vault.
///      Auto-mint enabled: Bebop settlement transferFrom auto-mints options from vault collateral.
contract YieldVault is
    ERC4626,
    ERC165,
    Ownable,
    ReentrancyGuardTransient,
    Pausable,
    IERC7540Redeem,
    IERC7540Operator,
    IERC1271
{
    using Math for uint256;

    // ============ ERRORS ============

    error InvalidAddress();
    error ZeroAmount();
    error Unauthorized();
    error NotWhitelisted();
    error InsufficientIdle();
    error InsufficientClaimable();
    error WithdrawDisabled();
    error AsyncOnly();

    // ============ EVENTS ============

    event OptionWhitelisted(address indexed option, bool allowed);
    event OptionsBurned(address indexed option, uint256 amount);

    // ============ STATE ============

    IOptionFactory public factory;
    address[] public activeOptions;
    mapping(address => bool) public whitelistedOptions;

    // ============ ASYNC REDEEM STATE ============

    mapping(address => uint256) private _pendingRedeemShares;
    mapping(address => uint256) private _claimableRedeemShares;
    mapping(address => uint256) private _claimableRedeemAssets;
    uint256 private _totalClaimableShares;
    uint256 private _totalClaimableAssets;

    // ============ OPERATORS ============

    mapping(address => mapping(address => bool)) private _operators;

    // ============ MODIFIERS ============

    modifier onlyOperatorOrOwner() {
        if (msg.sender != owner() && !_operators[owner()][msg.sender]) revert Unauthorized();
        _;
    }

    // ============ CONSTRUCTOR ============

    /// @param collateral_ Underlying collateral token (e.g. WETH)
    /// @param name_ Vault share token name
    /// @param symbol_ Vault share token symbol
    /// @param factory_ OptionFactory address
    constructor(IERC20 collateral_, string memory name_, string memory symbol_, address factory_)
        ERC4626(collateral_)
        ERC20(name_, symbol_)
        Ownable(msg.sender)
    {
        if (factory_ == address(0)) revert InvalidAddress();
        factory = IOptionFactory(factory_);
    }

    // ============ ERC4626 OVERRIDES ============

    /// @dev Virtual share offset to prevent first-depositor attack
    function _decimalsOffset() internal pure override returns (uint8) {
        return 3;
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

    function maxDeposit(address) public view override returns (uint256) {
        return paused() ? 0 : type(uint256).max;
    }

    function maxMint(address) public view override returns (uint256) {
        return paused() ? 0 : type(uint256).max;
    }

    /// @notice Withdraw disabled — use requestRedeem + redeem
    function maxWithdraw(address) public pure override returns (uint256) {
        return 0;
    }

    /// @notice Returns claimable shares (fulfilled redeem requests ready to claim)
    function maxRedeem(address controller) public view override returns (uint256) {
        return _claimableRedeemShares[controller];
    }

    function previewRedeem(uint256) public pure override returns (uint256) {
        revert AsyncOnly();
    }

    function previewWithdraw(uint256) public pure override returns (uint256) {
        revert AsyncOnly();
    }

    function withdraw(uint256, address, address) public pure override returns (uint256) {
        revert WithdrawDisabled();
    }

    // ============ ASYNC REDEEM (ERC-7540) ============
    //
    // Flow: requestRedeem (lock shares) → owner fulfillRedeem (snapshot price) → redeem (claim assets)
    //

    /// @notice Request to redeem shares. Locks shares in vault until fulfilled.
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

        emit RedeemRequest(controller, owner, 0, msg.sender, shares);
        return 0;
    }

    /// @notice Fulfill a pending redeem request, snapshotting the asset value at current price
    function fulfillRedeem(address controller) public onlyOwner nonReentrant {
        uint256 shares = _pendingRedeemShares[controller];
        if (shares == 0) revert ZeroAmount();

        uint256 assets = _convertToAssets(shares, Math.Rounding.Floor);
        uint256 availableIdle = IERC20(asset()).balanceOf(address(this)) - _totalClaimableAssets;
        if (availableIdle < assets) revert InsufficientIdle();

        _pendingRedeemShares[controller] = 0;

        _claimableRedeemShares[controller] += shares;
        _claimableRedeemAssets[controller] += assets;
        _totalClaimableShares += shares;
        _totalClaimableAssets += assets;
    }

    /// @notice Batch fulfill multiple pending redeem requests
    function fulfillRedeems(address[] calldata controllers) external onlyOwner {
        for (uint256 i = 0; i < controllers.length; i++) {
            fulfillRedeem(controllers[i]);
        }
    }

    /// @notice Claim assets from a fulfilled redeem request. Burns shares, transfers assets.
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

        assets = Math.mulDiv(_claimableRedeemAssets[controller], shares, claimableShares, Math.Rounding.Floor);

        _claimableRedeemShares[controller] -= shares;
        _claimableRedeemAssets[controller] -= assets;
        _totalClaimableShares -= shares;
        _totalClaimableAssets -= assets;

        _burn(address(this), shares);
        IERC20(asset()).safeTransfer(receiver, assets);

        emit Withdraw(msg.sender, receiver, controller, assets, shares);
    }

    /// @inheritdoc IERC7540Redeem
    function pendingRedeemRequest(uint256, address controller) external view override returns (uint256) {
        return _pendingRedeemShares[controller];
    }

    /// @inheritdoc IERC7540Redeem
    function claimableRedeemRequest(uint256, address controller) external view override returns (uint256) {
        return _claimableRedeemShares[controller];
    }

    // ============ OPERATORS (ERC-7540) ============

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

    // ============ OPERATOR ACTIONS ============

    /// @notice Pair-redeem option + redemption tokens held by vault to recover collateral
    function burn(address option, uint256 amount) external onlyOperatorOrOwner nonReentrant {
        if (!whitelistedOptions[option]) revert NotWhitelisted();
        if (amount == 0) revert ZeroAmount();
        IOption(option).redeem(amount);
        emit OptionsBurned(option, amount);
    }

    /// @notice Remove an option from the whitelist (operator or owner)
    function removeOption(address option) external onlyOperatorOrOwner {
        whitelistedOptions[option] = false;
        emit OptionWhitelisted(option, false);
    }

    // ============ EIP-1271: CONTRACT SIGNATURE ============

    /// @notice Validates signatures for Bebop settlement — authorized operators can sign on behalf of vault
    function isValidSignature(bytes32 hash, bytes calldata signature) external view override returns (bytes4) {
        address signer = ECDSA.recover(hash, signature);
        if (signer == owner() || _operators[owner()][signer]) {
            return 0x1626ba7e;
        }
        return 0xffffffff;
    }

    // ============ ERC-165 ============

    function supportsInterface(bytes4 interfaceId) public view override returns (bool) {
        return interfaceId == type(IERC7540Redeem).interfaceId || interfaceId == type(IERC7540Operator).interfaceId
            || interfaceId == type(IERC1271).interfaceId || super.supportsInterface(interfaceId);
    }

    // ============ ADMIN ============

    /// @notice Setup factory approvals so auto-mint can pull collateral
    function setupFactoryApproval() external onlyOwner {
        IERC20(asset()).forceApprove(address(factory), type(uint256).max);
        factory.approve(asset(), type(uint256).max);
    }

    /// @notice Enable auto-mint/redeem on the factory for this vault
    function enableAutoMintRedeem(bool enabled) external onlyOwner {
        factory.enableAutoMintRedeem(enabled);
    }

    /// @notice Whitelist an option and approve it for a settlement spender (e.g. Permit2, BalanceManager)
    /// @param option Option contract address
    /// @param spender Settlement contract to approve for pulling option tokens (address(0) to skip approval)
    function whitelistOption(address option, address spender) external onlyOwner {
        _activateOption(option);
        if (spender != address(0)) {
            IERC20(option).forceApprove(spender, type(uint256).max);
        }
        emit OptionWhitelisted(option, true);
    }

    /// @notice Remove expired/settled options from activeOptions to save gas on totalCommitted()
    function cleanupOptions() external {
        uint256 len = activeOptions.length;
        uint256 i = 0;
        while (i < len) {
            address opt = activeOptions[i];
            uint256 bal = IERC20(IOption(opt).redemption()).balanceOf(address(this));
            if (bal == 0 && block.timestamp >= IOption(opt).expirationDate()) {
                activeOptions[i] = activeOptions[len - 1];
                activeOptions.pop();
                len--;
            } else {
                i++;
            }
        }
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    // ============ VIEW ============

    /// @notice Total collateral committed across all active options
    function totalCommitted() public view returns (uint256 total) {
        for (uint256 i = 0; i < activeOptions.length; i++) {
            total += IERC20(IOption(activeOptions[i]).redemption()).balanceOf(address(this));
        }
    }

    /// @notice Collateral committed to a specific option
    function committed(address option) public view returns (uint256) {
        return IERC20(IOption(option).redemption()).balanceOf(address(this));
    }

    /// @notice Idle collateral available (not committed to options, not earmarked for redeems)
    function idleCollateral() external view returns (uint256) {
        return IERC20(asset()).balanceOf(address(this)) - _totalClaimableAssets;
    }

    function utilizationBps() external view returns (uint256) {
        uint256 total = totalAssets();
        if (total == 0) return 0;
        return (totalCommitted() * 10000) / total;
    }

    function getVaultStats()
        external
        view
        returns (uint256 totalAssets_, uint256 totalShares_, uint256 idle_, uint256 committed_, uint256 utilizationBps_)
    {
        totalAssets_ = totalAssets();
        totalShares_ = _activeSupply();
        idle_ = IERC20(asset()).balanceOf(address(this)) - _totalClaimableAssets;
        committed_ = totalCommitted();
        utilizationBps_ = totalAssets_ > 0 ? (committed_ * 10000) / totalAssets_ : 0;
    }

    // ============ INTERNAL ============

    function _activateOption(address option) internal {
        if (!whitelistedOptions[option]) {
            whitelistedOptions[option] = true;
            activeOptions.push(option);
        }
    }
}
