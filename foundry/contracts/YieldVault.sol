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
import { IReceipt } from "./interfaces/IReceipt.sol";
import { IFactory } from "./interfaces/IFactory.sol";
import { IERC7540Redeem, IERC7540Operator } from "./interfaces/IERC7540.sol";

using SafeERC20 for IERC20;

/**
 * @title  YieldVault — operator-managed option-writing vault
 * @author Greek.fi
 * @notice ERC4626 vault that accepts collateral (e.g. WETH), writes options against it, and
 *         earns yield from the premiums collected on each trade. Depositors share in that yield
 *         pro-rata via vault shares.
 *
 *         ### Architecture
 *
 *         - **ERC-4626** for the share accounting.
 *         - **ERC-7540** async redeems — vault collateral may be locked inside live options, so
 *           withdrawals go through `requestRedeem → owner fulfillRedeem → redeem`. The synchronous
 *           `withdraw` / `previewRedeem` paths are intentionally disabled.
 *         - **ERC-1271** contract signatures — the vault can act as a Bebop taker; authorised
 *           operators sign RFQ quotes on its behalf.
 *         - **Operator registry** — `setOperator` delegates the vault's trading powers (`execute`,
 *           `burn`, `redeemExpired`, `removeOption`, signing). The vault owner is always authorised.
 *         - **Auto-mint** — with `setupFactoryApproval` + `enableAutoMintBurn`, selling an option
 *             inside a Bebop `swapSingle` automatically mints it against vault collateral.
 *
 *         ### Flow
 *
 *         1. Users `deposit(asset, shares)` — receive vault shares.
 *         2. Operator routes RFQ trades through {execute} — Bebop settlement pulls options from the
 *            vault, auto-minting against idle collateral.
 *         3. After expiry, operator calls {redeemExpired} to recover leftover collateral + any
 *            consideration earned. {burn} is used to close matched pairs pre-expiry.
 *         4. Users who want out call {requestRedeem}. Once the operator has idle collateral, they
 *            call {fulfillRedeem} to snapshot the asset value. The user then claims via {redeem}.
 *
 * @dev    Deployments are per-collateral (one vault for WETH, another for USDC, etc.).
 */
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

    /// @notice Thrown when a required address is zero.
    error InvalidAddress();
    /// @notice Thrown when a mutation is called with `amount == 0`.
    error ZeroAmount();
    /// @notice Thrown when the caller is neither owner nor an approved operator.
    error Unauthorized();
    /// @notice Thrown when idle collateral is insufficient to fulfill a redeem request.
    error InsufficientIdle();
    /// @notice Thrown when a user tries to claim more shares than they have fulfilled.
    error InsufficientClaimable();
    /// @notice Thrown when synchronous `withdraw` is called — use the async redeem flow.
    error WithdrawDisabled();
    /// @notice Thrown when a preview function requiring a sync path is called in async-only mode.
    error AsyncOnly();

    // ============ EVENTS ============

    /// @notice Emitted when an option is added to the active set via {addOption}.
    event OptionAdded(address indexed option);
    /// @notice Emitted when an option is removed from the active set via {removeOption} or {cleanupOptions}.
    event OptionRemoved(address indexed option);
    /// @notice Emitted when the vault pair-redeems held Option + Receipt tokens via {burn}.
    event OptionsBurned(address indexed option, uint256 amount);

    // ============ STATE ============

    /// @notice Factory used when configuring auto-mint approvals.
    IFactory public factory;
    /// @notice Options this vault has written / is tracking. Drives {totalCommitted} accounting.
    address[] public activeOptions;

    // ============ ASYNC REDEEM STATE ============

    /// @dev Controller → shares awaiting fulfillment.
    mapping(address => uint256) private _pendingRedeemShares;
    /// @dev Controller → shares that have been fulfilled and can now be claimed.
    mapping(address => uint256) private _claimableRedeemShares;
    /// @dev Controller → asset amount earmarked at fulfillment (price snapshot).
    mapping(address => uint256) private _claimableRedeemAssets;
    /// @dev Sum of all `_claimableRedeemShares` across controllers — subtracted from `totalSupply`
    ///      in the share math so claimable shares don't dilute active depositors.
    uint256 private _totalClaimableShares;
    /// @dev Sum of all `_claimableRedeemAssets` — subtracted from balance in `totalAssets`.
    uint256 private _totalClaimableAssets;

    // ============ OPERATORS ============

    /// @dev `_operators[controller][operator] -> bool`.
    mapping(address => mapping(address => bool)) private _operators;

    // ============ MODIFIERS ============

    /// @dev Permits owner + operators approved *by the owner*.
    modifier onlyOperatorOrOwner() {
        if (msg.sender != owner() && !_operators[owner()][msg.sender]) revert Unauthorized();
        _;
    }

    // ============ CONSTRUCTOR ============

    /// @notice Deploy a vault for a single collateral asset.
    /// @param collateral_ Underlying ERC20 (e.g. WETH).
    /// @param name_       Vault share token name.
    /// @param symbol_     Vault share token symbol.
    /// @param factory_    {Factory} used for auto-mint approvals (non-zero).
    constructor(IERC20 collateral_, string memory name_, string memory symbol_, address factory_)
        ERC4626(collateral_)
        ERC20(name_, symbol_)
        Ownable(msg.sender)
    {
        if (factory_ == address(0)) revert InvalidAddress();
        factory = IFactory(factory_);
    }

    // ============ ERC4626 OVERRIDES ============

    /// @dev Virtual-share offset prevents first-depositor inflation attacks (OZ ERC-4626 convention).
    function _decimalsOffset() internal pure override returns (uint8) {
        return 3;
    }

    /// @notice Assets actively backing shares: idle balance + collateral committed to live options,
    ///         minus amounts earmarked for fulfilled (but not yet claimed) redeems.
    function totalAssets() public view override returns (uint256) {
        return IERC20(asset()).balanceOf(address(this)) + totalCommitted() - _totalClaimableAssets;
    }

    /// @dev Active share supply — excludes shares already locked in the vault as claimable redeems,
    ///      so fulfilled-but-unclaimed redeems don't inflate the price per share.
    function _activeSupply() internal view returns (uint256) {
        return totalSupply() - _totalClaimableShares;
    }

    /// @inheritdoc ERC4626
    function _convertToShares(uint256 assets, Math.Rounding rounding) internal view override returns (uint256) {
        return assets.mulDiv(_activeSupply() + 10 ** _decimalsOffset(), totalAssets() + 1, rounding);
    }

    /// @inheritdoc ERC4626
    function _convertToAssets(uint256 shares, Math.Rounding rounding) internal view override returns (uint256) {
        return shares.mulDiv(totalAssets() + 1, _activeSupply() + 10 ** _decimalsOffset(), rounding);
    }

    /// @inheritdoc ERC4626
    /// @dev Deposits are disabled while paused.
    function maxDeposit(address) public view override returns (uint256) {
        return paused() ? 0 : type(uint256).max;
    }

    /// @inheritdoc ERC4626
    /// @dev Mints are disabled while paused.
    function maxMint(address) public view override returns (uint256) {
        return paused() ? 0 : type(uint256).max;
    }

    /// @notice Synchronous withdraw is disabled in favour of the ERC-7540 flow.
    /// @dev Returns 0 so interfaces don't offer it as an option.
    function maxWithdraw(address) public pure override returns (uint256) {
        return 0;
    }

    /// @notice Shares that `controller` has had fulfilled and can now claim via {redeem}.
    function maxRedeem(address controller) public view override returns (uint256) {
        return _claimableRedeemShares[controller];
    }

    /// @notice Preview for synchronous redeems is not defined — use the async flow.
    function previewRedeem(uint256) public pure override returns (uint256) {
        revert AsyncOnly();
    }

    /// @notice Preview for synchronous withdraws is not defined — use the async flow.
    function previewWithdraw(uint256) public pure override returns (uint256) {
        revert AsyncOnly();
    }

    /// @notice Synchronous withdraw is disabled.
    function withdraw(uint256, address, address) public pure override returns (uint256) {
        revert WithdrawDisabled();
    }

    // ============ ASYNC REDEEM (ERC-7540) ============
    //
    // Flow: requestRedeem (lock shares) → owner fulfillRedeem (snapshot price) → redeem (claim assets)
    //

    /// @inheritdoc IERC7540Redeem
    /// @notice Step 1/3 of the async redeem: lock `shares` in the vault until an operator fulfils.
    /// @dev    Shares move from `owner` into `address(this)`. Caller can be `owner` directly or an
    ///         operator approved via {setOperator}. Returns `0` (synchronous request id not used).
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

    /// @notice Step 2/3: owner fulfils a pending request, snapshotting its asset value at the
    ///         current share price. Requires idle collateral ≥ quoted assets.
    /// @param controller Controller whose pending request is being fulfilled.
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

    /// @notice Batch {fulfillRedeem} — useful when rebalancing the vault periodically.
    /// @param controllers Controllers whose requests should be fulfilled.
    function fulfillRedeems(address[] calldata controllers) external onlyOwner {
        for (uint256 i = 0; i < controllers.length; i++) {
            fulfillRedeem(controllers[i]);
        }
    }

    /// @notice Step 3/3: claim the fulfilled redeem. Burns shares, transfers assets to `receiver`.
    /// @dev    Caller can be `controller` directly or an operator approved by `controller`.
    ///         `assets` are computed pro-rata in case the controller is partially claiming a larger
    ///         fulfilled bucket.
    /// @param shares     Shares to claim (≤ `maxRedeem(controller)`).
    /// @param receiver   Address receiving the underlying collateral.
    /// @param controller Controller whose claimable bucket is being drawn from.
    /// @return assets    Underlying collateral paid out.
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
    /// @dev Self-approval is rejected; returns `true` on success.
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

    /// @notice Execute an arbitrary call from the vault. Used to route RFQ trades (e.g. calling
    ///         `BebopSettlement.swapSingle` with the vault as taker).
    /// @dev    Owner or owner-approved operator only. Bubbles up the callee's revert reason.
    /// @param target The contract to call.
    /// @param data   Raw calldata.
    /// @return result Raw return data.
    ///
    /// Example:
    /// ```solidity
    /// vault.execute(BEBOP_SETTLEMENT, abi.encodeCall(IBebop.swapSingle, (order, sig)));
    /// ```
    function execute(address target, bytes calldata data) external onlyOperatorOrOwner returns (bytes memory) {
        (bool ok, bytes memory result) = target.call(data);
        if (!ok) {
            assembly { revert(add(result, 32), mload(result)) }
        }
        return result;
    }

    /// @notice Pre-expiry: burn matched Option + Receipt tokens held by the vault to recover
    ///         the underlying collateral (calls {Option.redeem}).
    /// @param option Option contract whose Option + Receipt are paired in the vault.
    /// @param amount Collateral-denominated pair amount to redeem.
    function burn(address option, uint256 amount) external onlyOperatorOrOwner nonReentrant {
        if (amount == 0) revert ZeroAmount();
        IOption(option).burn(amount);
        emit OptionsBurned(option, amount);
    }

    /// @notice Post-window: redeem all Receipt tokens this vault holds for `option`, pulling
    ///         leftover collateral + any consideration earned during exercise.
    /// @param option Option contract whose short side is held by the vault.
    function redeemExpired(address option) external onlyOperatorOrOwner {
        address r = IOption(option).receipt();
        uint256 balance = IERC20(r).balanceOf(address(this));
        if (balance == 0) revert ZeroAmount();
        IReceipt(r).redeem(address(this), balance);
    }

    /// @notice Untrack an option (does not affect token balances).
    /// @dev    Swap-and-pop — ordering is not preserved. Called automatically by {cleanupOptions}
    ///         once the option has expired and the vault's short-side balance is zero.
    function removeOption(address option) external onlyOperatorOrOwner {
        uint256 len = activeOptions.length;
        for (uint256 i = 0; i < len; i++) {
            if (activeOptions[i] == option) {
                activeOptions[i] = activeOptions[len - 1];
                activeOptions.pop();
                emit OptionRemoved(option);
                return;
            }
        }
    }

    // ============ EIP-1271: CONTRACT SIGNATURE ============

    /// @notice Let contracts (e.g. Bebop settlement) verify the vault's signature. Accepts any
    ///         ECDSA signature produced by the owner or an owner-approved operator.
    /// @param hash      Message hash being verified.
    /// @param signature 65-byte ECDSA signature.
    /// @return magicValue `0x1626ba7e` on success, `0xffffffff` otherwise (EIP-1271 convention).
    function isValidSignature(bytes32 hash, bytes calldata signature) external view override returns (bytes4) {
        address signer = ECDSA.recover(hash, signature);
        if (signer == owner() || _operators[owner()][signer]) {
            return 0x1626ba7e;
        }
        return 0xffffffff;
    }

    // ============ ERC-165 ============

    /// @inheritdoc ERC165
    function supportsInterface(bytes4 interfaceId) public view override returns (bool) {
        return interfaceId == type(IERC7540Redeem).interfaceId || interfaceId == type(IERC7540Operator).interfaceId
            || interfaceId == type(IERC1271).interfaceId || super.supportsInterface(interfaceId);
    }

    // ============ ADMIN ============

    /// @notice One-time setup: grant the factory infinite allowance over the vault's collateral AND
    ///         record the same allowance in the factory's own allowance registry.
    /// @dev    Required before auto-mint can pull collateral inside a settlement call.
    function setupFactoryApproval() external onlyOwner {
        IERC20(asset()).forceApprove(address(factory), type(uint256).max);
        factory.approve(asset(), type(uint256).max);
    }

    /// @notice Opt the vault into {Option}'s auto-mint-on-transfer / auto-redeem-on-receive hooks.
    /// @param enabled `true` to opt in, `false` to opt out.
    function enableAutoMintBurn(bool enabled) external onlyOwner {
        factory.enableAutoMintBurn(enabled);
    }

    /// @notice Approve `spender` to pull `amount` of `token` from the vault.
    /// @dev    Used to configure Permit2 / Bebop balance manager approvals for settlement flows.
    /// @param token   ERC20 to approve.
    /// @param spender Address being approved.
    /// @param amount  Allowance (use `type(uint256).max` for infinite).
    function approveToken(address token, address spender, uint256 amount) external onlyOwner {
        IERC20(token).forceApprove(spender, amount);
    }

    /// @notice Start tracking `option` in `activeOptions` and optionally approve a settlement
    ///         contract to pull the vault's Option tokens.
    /// @param option   Option contract to activate.
    /// @param spender  Settlement contract receiving an infinite Option-token approval, or
    ///                 `address(0)` to skip approvals (the option is just tracked).
    function addOption(address option, address spender) external onlyOwner {
        _activateOption(option);
        if (spender != address(0)) {
            IERC20(option).forceApprove(spender, type(uint256).max);
        }
    }

    /// @notice Untrack options whose short-side balance is zero *and* which are past expiry.
    /// @dev    Publicly callable — anyone can pay the gas to compact the active set. Keeps
    ///         {totalCommitted} cheap over time.
    function cleanupOptions() external {
        uint256 len = activeOptions.length;
        uint256 i = 0;
        while (i < len) {
            address opt = activeOptions[i];
            uint256 bal = IERC20(IOption(opt).receipt()).balanceOf(address(this));
            if (bal == 0 && block.timestamp >= IOption(opt).expirationDate()) {
                activeOptions[i] = activeOptions[len - 1];
                activeOptions.pop();
                len--;
            } else {
                i++;
            }
        }
    }

    /// @notice Pause deposits and mints. Existing deposits continue to earn and can still redeem.
    function pause() external onlyOwner {
        _pause();
    }

    /// @notice Reverse of {pause}.
    function unpause() external onlyOwner {
        _unpause();
    }

    // ============ VIEW ============

    /// @notice Sum of the vault's Receipt-token balances across every tracked option —
    ///         i.e. collateral currently locked backing live short positions.
    function totalCommitted() public view returns (uint256 total) {
        for (uint256 i = 0; i < activeOptions.length; i++) {
            total += IERC20(IOption(activeOptions[i]).receipt()).balanceOf(address(this));
        }
    }

    /// @notice Collateral committed to a single option (Receipt-token balance for that option).
    function committed(address option) public view returns (uint256) {
        return IERC20(IOption(option).receipt()).balanceOf(address(this));
    }

    /// @notice Collateral sitting in the vault that is free to use (idle balance minus earmarked redeems).
    function idleCollateral() external view returns (uint256) {
        return IERC20(asset()).balanceOf(address(this)) - _totalClaimableAssets;
    }

    /// @notice Share of total assets currently committed to live options, in basis points.
    /// @return 0 when the vault is empty, otherwise `totalCommitted / totalAssets * 1e4`.
    function utilizationBps() external view returns (uint256) {
        uint256 total = totalAssets();
        if (total == 0) return 0;
        return (totalCommitted() * 10000) / total;
    }

    /// @notice One-shot snapshot for frontends.
    /// @return totalAssets_    Total asset value ({totalAssets}).
    /// @return totalShares_    Active share supply (excludes claimable redeems).
    /// @return idle_           Idle asset balance (excludes earmarked redeems).
    /// @return committed_      Assets committed to live options.
    /// @return utilizationBps_ committed_ / totalAssets_ * 1e4.
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

    /// @dev Idempotently append `option` to `activeOptions`.
    function _activateOption(address option) internal {
        for (uint256 i = 0; i < activeOptions.length; i++) {
            if (activeOptions[i] == option) return;
        }
        activeOptions.push(option);
        emit OptionAdded(option);
    }
}
