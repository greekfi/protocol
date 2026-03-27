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

    error NotWhitelisted();
    error InsufficientIdle();
    error InvalidAddress();
    error ZeroAmount();
    error Unauthorized();
    error InsufficientClaimable();
    error WithdrawDisabled();
    error AsyncOnly();

    // ============ EVENTS ============

    event OptionWhitelisted(address indexed option, bool allowed);
    event OptionsBurned(address indexed option, uint256 amount);

    // ============ CORE ============

    IOptionFactory public factory;

    // ============ BEBOP INTEGRATION ============

    address public bebopApprovalTarget;

    // ============ BOOKKEEPING ============

    address[] public activeOptions;
    mapping(address => bool) public whitelistedOptions;

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

    /// @notice Total collateral committed across all active options (computed from redemption balances)
    function totalCommitted() public view returns (uint256 total) {
        for (uint256 i = 0; i < activeOptions.length; i++) {
            total += IERC20(IOption(activeOptions[i]).redemption()).balanceOf(address(this));
        }
    }

    /// @notice Collateral committed to a specific option
    function committed(address option) public view returns (uint256) {
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

    function previewRedeem(uint256) public pure override returns (uint256) {
        revert AsyncOnly();
    }

    function previewWithdraw(uint256) public pure override returns (uint256) {
        revert AsyncOnly();
    }

    function withdraw(uint256, address, address) public pure override returns (uint256) {
        revert WithdrawDisabled();
    }

    /// @notice Claim assets from a fulfilled redeem request
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

    /// @notice Fulfill a pending redeem request, snapshotting the asset value
    function fulfillRedeem(address controller) public onlyOwner nonReentrant {
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

    /// @notice Batch fulfill multiple pending redeem requests
    function fulfillRedeems(address[] calldata controllers) external onlyOwner {
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

    /// @notice Pair-redeem option + redemption tokens to recover collateral
    function burn(address option, uint256 amount) external onlyOperatorOrOwner nonReentrant {
        if (!whitelistedOptions[option]) revert NotWhitelisted();
        if (amount == 0) revert ZeroAmount();
        IOption(option).redeem(amount);
        emit OptionsBurned(option, amount);
    }

    /// @notice Enable auto-mint/redeem on the factory for this vault
    function enableAutoMintRedeem(bool enabled) external onlyOwner {
        factory.enableAutoMintRedeem(enabled);
    }

    // ============ EIP-1271: CONTRACT SIGNATURE VALIDATION ============

    /// @notice Validates signatures for Bebop settlement — allows authorized operators to sign on behalf of vault
    /// @inheritdoc IERC1271
    function isValidSignature(bytes32 hash, bytes calldata signature) external view override returns (bytes4) {
        address signer = ECDSA.recover(hash, signature);
        if (signer == owner() || _operators[owner()][signer]) {
            return 0x1626ba7e;
        }
        return 0xffffffff;
    }

    // ============ ADMIN ============

    /// @notice Setup factory approvals so the vault can mint options
    /// @dev Must be called after deployment by owner
    function setupFactoryApproval() external onlyOwner {
        IERC20(asset()).forceApprove(address(factory), type(uint256).max);
        factory.approve(asset(), type(uint256).max);
    }

    function whitelistOption(address option, bool allowed) external onlyOwner {
        if (allowed) {
            _activateOption(option);
        } else {
            whitelistedOptions[option] = false;
        }
        emit OptionWhitelisted(option, allowed);
    }

    function setBebopApprovalTarget(address target) external onlyOwner {
        bebopApprovalTarget = target;
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    // ============ VIEW ============

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

    function getPositionInfo(address option)
        external
        view
        returns (uint256 committed_, uint256 redemptionBalance_, bool expired_)
    {
        address redemption = IOption(option).redemption();
        committed_ = IERC20(redemption).balanceOf(address(this));
        redemptionBalance_ = committed_;
        expired_ = block.timestamp >= IOption(option).expirationDate();
    }

    // ============ INTERNAL ============

    function _activateOption(address option) internal {
        if (!whitelistedOptions[option]) {
            whitelistedOptions[option] = true;
            activeOptions.push(option);
        }
    }
}
