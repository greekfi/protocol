// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuardTransient} from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";

import {Option} from "./Option.sol";
import {Receipt} from "./Receipt.sol";
import {CreateParams} from "./interfaces/IFactory.sol";

using SafeERC20 for ERC20;

/**
 * @title  Factory — deployer, allowance hub, operator registry
 * @author Greek.fi
 * @notice The only on-chain contract users need to interact with to *create* options. Once deployed,
 *         every Option + Receipt pair runs off pre-compiled template clones, so creation is
 *         cheap and the factory is never an upgradeable rug vector (the templates are immutable).
 *
 *         The factory also plays three lasting roles post-creation:
 *
 *         1. **Single allowance point.** Users `approve(collateralToken, amount)` on the factory once,
 *            and any Option / Receipt pair created by this factory can pull from that allowance
 *            via {transferFrom}. No need to approve every new option individually.
 *
 *         2. **Operator registry.** {approveOperator} gives an address blanket authority to move
 *            any Option produced by this factory on your behalf — the ERC-1155-style "setApprovalForAll"
 *            pattern. Used by trading venues and aggregators.
 *
 *         3. **Auto-mint / auto-redeem opt-in.** {enableAutoMintBurn} flips a per-account flag that
 *            Option consults on transfer to auto-mint deficits and auto-redeem matched Option+Receipt
 *            on the receiving side.
 *
 *         ### Token blocklist
 *
 *         The factory owner can {blockToken} / {unblockToken} to prevent options from being created
 *         against known-problematic tokens (fee-on-transfer, rebasing, exploited). It never affects
 *         already-created options — only new creations.
 *
 *         ### Exercise window
 *
 *         There is no oracle. Settlement is purely time-gated:
 *
 *         - `isEuro = false` (American) — exercise allowed from creation through `exerciseDeadline`.
 *         - `isEuro = true`  (European) — exercise allowed only between `expirationDate` and
 *           `exerciseDeadline`.
 *
 *         `windowSeconds` on {CreateParams} sets how long after expiration the window stays open;
 *         passing `0` selects {DEFAULT_EXERCISE_WINDOW} (8 hours). After
 *         `expirationDate + windowSeconds`, exercise reverts (for both flavours) and short-side
 *         redemption opens.
 */
contract Factory is Ownable, ReentrancyGuardTransient {
    /// @notice Template Receipt contract; per-option instances are EIP-1167 clones of this.
    address public immutable RECEIPT_CLONE;
    /// @notice Template Option contract; per-option instances are EIP-1167 clones of this.
    address public immutable OPTION_CLONE;
    /// @notice Default post-expiry exercise window when `CreateParams.windowSeconds == 0`.
    uint40 public constant DEFAULT_EXERCISE_WINDOW = 8 hours;

    /// @notice `true` if the address is a Receipt clone this factory created. Doubles as the auth
    ///         gate for {transferFrom} — only registered Receipts can pull from factory allowances.
    mapping(address => bool) public receipts;

    /// @notice `true` if the address is an Option clone this factory created.
    mapping(address => bool) public options;

    /// @notice Tokens rejected for new option creation. Does not affect already-created options.
    mapping(address => bool) public blocklist;

    /// @dev Per-token allowance table: `_allowances[token][owner] -> amount`.
    mapping(address => mapping(address => uint256)) private _allowances;

    /// @dev Operator approval table: `_approvedOperators[owner][operator] -> bool`.
    mapping(address => mapping(address => bool)) private _approvedOperators;

    /// @dev Exercise-allowance table: `_exerciseAllowed[holder][operator] -> bool`. Lets `operator`
    ///      burn `holder`'s options via the on-behalf {Option.exercise} overload.
    mapping(address => mapping(address => bool)) private _exerciseAllowed;

    /// @notice Per-account opt-in for auto-mint on transfer and auto-redeem on receive in {Option}.
    mapping(address => bool) public autoMintBurn;

    /// @notice Thrown when {createOption} is called against a blocklisted collateral or consideration token.
    error BlocklistedToken();
    /// @notice Thrown when a zero address is supplied where a real contract is required.
    error InvalidAddress();
    /// @notice Thrown when `collateral == consideration` (no real option pair).
    error InvalidTokens();
    /// @notice Thrown when {transferFrom} is called with `allowance < amount`.
    error InsufficientAllowance();

    /// @notice Emitted for every newly-created option.
    event OptionCreated(
        address indexed collateral,
        address indexed consideration,
        uint40 expirationDate,
        uint96 strike,
        bool isPut,
        bool isEuro,
        uint40 windowSeconds,
        address indexed option,
        address receipt
    );
    /// @notice Emitted on {blockToken} / {unblockToken}.
    event TokenBlocked(address token, bool blocked);
    /// @notice Emitted on {approveOperator}.
    event OperatorApproval(address indexed owner, address indexed operator, bool approved);
    /// @notice Emitted on {allowExercise}.
    event ExerciseApproval(address indexed holder, address indexed exercisor, bool allowed);
    /// @notice Emitted on {enableAutoMintBurn}.
    event AutoMintBurnUpdated(address indexed account, bool enabled);
    /// @notice Emitted on {approve} (factory-level allowance set by token owner).
    event Approval(address indexed token, address indexed owner, uint256 amount);

    /// @notice Bind the factory to its immutable templates.
    /// @param receiptClone_ Deployed Receipt template.
    /// @param optionClone_  Deployed Option template.
    constructor(address receiptClone_, address optionClone_) Ownable(msg.sender) {
        if (receiptClone_ == address(0) || optionClone_ == address(0)) revert InvalidAddress();
        RECEIPT_CLONE = receiptClone_;
        OPTION_CLONE = optionClone_;
    }

    // ============ OPTION CREATION ============

    /// @notice Deploy a new Option + Receipt pair.
    /// @dev    Clones the templates and initialises both sides. Emits {OptionCreated}. The caller
    ///         becomes the {Option}'s admin owner.
    /// @param p See {CreateParams}:
    ///          - `collateral`, `consideration`: ERC20 addresses; must differ and not be blocklisted.
    ///          - `expirationDate`: unix timestamp; must be in the future.
    ///          - `strike`: 18-decimal fixed point (consideration per collateral, inverted for puts).
    ///          - `isPut`: option flavour.
    ///          - `isEuro`: `true` for European (no pre-expiry exercise), `false` for American.
    ///          - `windowSeconds`: post-expiry exercise window length; `0` → {DEFAULT_EXERCISE_WINDOW}.
    /// @return The new {Option} address.
    function createOption(CreateParams memory p) public nonReentrant returns (address) {
        if (blocklist[p.collateral] || blocklist[p.consideration]) revert BlocklistedToken();
        if (p.collateral == p.consideration) revert InvalidTokens();

        uint40 windowSeconds = p.windowSeconds == 0 ? DEFAULT_EXERCISE_WINDOW : p.windowSeconds;

        address receipt_ = Clones.clone(RECEIPT_CLONE);
        address option_ = Clones.clone(OPTION_CLONE);

        Receipt(receipt_)
            .init(
                p.collateral,
                p.consideration,
                p.expirationDate,
                p.strike,
                p.isPut,
                p.isEuro,
                windowSeconds,
                option_,
                address(this)
            );
        Option(option_).init(receipt_, msg.sender);

        receipts[receipt_] = true;
        options[option_] = true;

        emit OptionCreated(
            p.collateral,
            p.consideration,
            p.expirationDate,
            p.strike,
            p.isPut,
            p.isEuro,
            windowSeconds,
            option_,
            receipt_
        );
        return option_;
    }

    /// @notice Batch form of {createOption}. Same ordering in → same ordering out.
    /// @param params Array of {CreateParams}.
    /// @return result Array of newly-created Option addresses, aligned with `params`.
    function createOptions(CreateParams[] memory params) external returns (address[] memory result) {
        result = new address[](params.length);
        for (uint256 i = 0; i < params.length; i++) {
            result[i] = createOption(params[i]);
        }
    }

    // ============ CENTRALIZED TRANSFER ============

    /// @notice Pull `amount` of `token` from `from` to `to`. Only callable by Receipt clones
    ///         that this factory has created.
    /// @dev    Decrements `_allowances[token][from]` (unless it is `type(uint256).max`).
    ///         This is the mechanism by which a single user approval on the factory flows to every
    ///         option pair it creates, rather than requiring approvals on each Receipt clone.
    /// @param from   Token owner.
    /// @param to     Recipient (typically the calling Receipt contract).
    /// @param amount Token amount to transfer (≤ `uint160.max`, matching Permit2 semantics).
    /// @param token  Token to move.
    /// @return success Always `true` on success; reverts otherwise.
    function transferFrom(address from, address to, uint160 amount, address token)
        external
        nonReentrant
        returns (bool)
    {
        if (!receipts[msg.sender]) revert InvalidAddress();
        uint256 currentAllowance = _allowances[token][from];
        if (currentAllowance < amount) revert InsufficientAllowance();
        if (currentAllowance != type(uint256).max) {
            _allowances[token][from] = currentAllowance - amount;
        }
        ERC20(token).safeTransferFrom(from, to, amount);
        return true;
    }

    /// @notice Factory-level allowance lookup: how much of `token` can the factory pull from `owner_`?
    /// @param token  Token.
    /// @param owner_ Token owner.
    /// @return Current allowance.
    function allowance(address token, address owner_) public view returns (uint256) {
        return _allowances[token][owner_];
    }

    /// @notice Permit2-style allowance: caller authorises the factory to pull up to `amount` of
    ///         `token` (collateral or consideration) on their behalf when any Option / Receipt
    ///         pair created by this factory needs to move it. The user must also have granted the
    ///         underlying `token.approve(factory, ...)` so `safeTransferFrom` can land.
    /// @param token  ERC20 to be approved.
    /// @param amount Allowance to grant (use `type(uint256).max` for infinite).
    function approve(address token, uint256 amount) public {
        if (token == address(0)) revert InvalidAddress();
        _allowances[token][msg.sender] = amount;
        emit Approval(token, msg.sender, amount);
    }

    // ============ OPERATOR APPROVAL ============

    /// @notice Grant or revoke `operator` blanket authority to move any of the caller's Option tokens
    ///         across every option this factory has created (ERC-1155-style `setApprovalForAll`).
    /// @dev    Used by trading venues to avoid per-option approvals. Operators also skip the
    ///         per-transfer `_spendAllowance` step on {Option.transferFrom}.
    /// @param operator Address being approved/revoked (must differ from `msg.sender`).
    /// @param approved `true` to grant, `false` to revoke.
    function approveOperator(address operator, bool approved) external {
        if (operator == address(0)) revert InvalidAddress();
        if (operator == msg.sender) revert InvalidAddress();
        _approvedOperators[msg.sender][operator] = approved;
        emit OperatorApproval(msg.sender, operator, approved);
    }

    /// @notice Is `operator` an approved operator for `owner_`?
    function approvedOperator(address owner_, address operator) external view returns (bool) {
        return _approvedOperators[owner_][operator];
    }

    /// @notice Authorise `exercisor` to exercise the caller's options on their behalf.
    /// @dev    Consumed by the on-behalf {Option.exercise(address,uint256)} overloads, which burn
    ///         the holder's option tokens, pull consideration from `exercisor`, and deliver the
    ///         collateral to `exercisor`. Distinct from {approveOperator}: that grants transfer
    ///         authority over the holder's option tokens, this grants the right to *consume* them
    ///         (burn). Defaults to `false`; revoke by passing `allowed = false`.
    /// @param exercisor Account being authorised (must differ from `msg.sender`).
    /// @param allowed   `true` to grant, `false` to revoke.
    function allowExercise(address exercisor, bool allowed) external {
        if (exercisor == address(0)) revert InvalidAddress();
        if (exercisor == msg.sender) revert InvalidAddress();
        _exerciseAllowed[msg.sender][exercisor] = allowed;
        emit ExerciseApproval(msg.sender, exercisor, allowed);
    }

    /// @notice Is `exercisor` authorised to burn `holder`'s options on their behalf? Set/cleared
    ///         only via {allowExercise} — independent of {approveOperator}, which grants transfer
    ///         (not burn) authority.
    function exerciseAllowed(address holder, address exercisor) external view returns (bool) {
        return _exerciseAllowed[holder][exercisor];
    }

    /// @notice Opt in to {Option}'s auto-mint-on-send and auto-redeem-on-receive transfer behaviour.
    function enableAutoMintBurn(bool enabled) external {
        autoMintBurn[msg.sender] = enabled;
        emit AutoMintBurnUpdated(msg.sender, enabled);
    }

    // ============ BLOCKLIST ============

    /// @notice Block `token` from being used as collateral or consideration for new options.
    /// @dev    Owner-only. Does not retroactively affect existing options — use {Option.lock} for that.
    function blockToken(address token) external onlyOwner nonReentrant {
        if (token == address(0)) revert InvalidAddress();
        blocklist[token] = true;
        emit TokenBlocked(token, true);
    }

    /// @notice Reverse of {blockToken}.
    function unblockToken(address token) external onlyOwner nonReentrant {
        if (token == address(0)) revert InvalidAddress();
        blocklist[token] = false;
        emit TokenBlocked(token, false);
    }

    /// @notice Is `token` on the blocklist?
    function isBlocked(address token) external view returns (bool) {
        return blocklist[token];
    }
}
