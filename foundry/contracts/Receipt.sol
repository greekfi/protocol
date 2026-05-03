// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { ReentrancyGuardTransient } from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";
import { IERC20, ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

import { Clone } from "./lib/Clone.sol";

using SafeERC20 for IERC20;

import { TokenData } from "./interfaces/IOption.sol";
import { OptionUtils } from "./OptionUtils.sol";

/// @dev Narrow view of {Factory} used by {Receipt} to pull collateral/consideration tokens via the
///      factory's centralised allowance registry.
interface IFactoryTransfer {
    function transferFrom(address from, address to, uint160 amount, address token) external;
}

/**
 * @title  Receipt — short-side ERC20 (collateral receipt)
 * @author Greek.fi
 * @notice The short side of a Greek option pair. Holding this token is a receipt for the
 *         collateral you deposited when minting: you received the premium (off-chain) and now
 *         bear the obligation of the exercise payoff. It holds all collateral for the pair and
 *         receives the consideration paid on exercise.
 *
 *         No oracle is consulted at any point. Settlement is purely time-gated:
 *
 *         | Mode      | `isEuro` | Pre-expiry exercise | In-window exercise | Post-window      |
 *         | --------- | -------- | ------------------- | ------------------ | ---------------- |
 *         | American  | `false`  | allowed             | allowed            | short pro-rata   |
 *         | European  | `true`   | reverts             | allowed            | short pro-rata   |
 *
 *         The exercise window closes for everyone at `exerciseDeadline = expirationDate + windowSeconds`.
 *         Pair-redeem (`burn`, called by Option) stays available pre-deadline.
 *
 *         ### Rounding
 *
 *         - Collections from users (exercise): round UP (`toNeededConsideration`).
 *         - Payouts to users (redeem): round DOWN (floor).
 *
 * @dev    Deployed once as a template; per-option instances are clones produced by
 *         `ClonesWithImmutableArgs`. Every per-option value (strike, collateral, consideration,
 *         expirationDate, exerciseDeadline, isPut, isEuro, decimals, option) is appended to the
 *         clone's runtime bytecode at deploy time and read via `Clone._getArg*` helpers
 *         (CALLDATALOAD, ~3 gas). There is no `init` function — the clone is fully configured
 *         the moment its bytecode is written.
 *
 *         ### Immutable args layout (packed, 112 bytes)
 *           offset  0   strike            uint256  (32B)
 *           offset 32   collateral        address  (20B)
 *           offset 52   consideration     address  (20B)
 *           offset 72   option            address  (20B)
 *           offset 92   expirationDate    uint64   (8B, holds a uint40)
 *           offset 100  exerciseDeadline  uint64   (8B, holds a uint40)
 *           offset 108  isPut             uint8    (1B, 0 or 1)
 *           offset 109  isEuro            uint8    (1B, 0 or 1)
 *           offset 110  collDecimals      uint8    (1B)
 *           offset 111  consDecimals      uint8    (1B)
 */
contract Receipt is ERC20, ReentrancyGuardTransient, Clone {
    /// @notice Factory that created this option, used to pull tokens through its Permit2-style
    ///         allowance registry. Set in the template constructor (= the factory that deployed
    ///         it) and inherited by every clone via the template's runtime bytecode.
    IFactoryTransfer public immutable factory;

    /// @notice Decimal basis of the strike — fixed at 18 and independent of token decimals.
    uint8 public constant STRIKE_DECIMALS = 18;

    /// @notice Thrown when a privileged path is called by anyone other than the paired {Option}.
    error UnauthorizedCaller();
    /// @notice Thrown when a pre-expiry-only path (mint) runs after expiration.
    error ContractExpired();
    /// @notice Thrown when an account does not hold enough Receipt tokens for the operation.
    error InsufficientBalance();
    /// @notice Thrown on `amount == 0` (or any derived zero-amount the invariant requires to be positive).
    error InvalidValue();
    /// @notice Thrown when a zero address is supplied where a real token/contract is required.
    error InvalidAddress();
    /// @notice Thrown if the transferred amount doesn't match what arrived — fee-on-transfer tokens are rejected.
    error FeeOnTransferNotSupported();
    /// @notice Thrown when this contract does not hold enough collateral for an exercise payout.
    error InsufficientCollateral();
    /// @notice Thrown when the exerciser's consideration balance (or the contract's) is short.
    error InsufficientConsideration();
    /// @notice Thrown when casting `amount` to `uint160` would overflow the Permit2 cap.
    error ArithmeticOverflow();
    /// @notice Thrown when exercise is attempted after `exerciseDeadline`.
    error ExerciseWindowClosed();
    /// @notice Thrown when a post-window-only path is called before the window closes.
    error ExerciseWindowOpen();
    /// @notice Thrown when pre-expiry exercise is attempted on a European option.
    error EuropeanExerciseDisabled();

    /// @notice Emitted on every path that returns collateral or consideration to a user.
    /// @param option The paired Option contract.
    /// @param token  The token actually transferred out (`collateral` or `consideration`).
    /// @param holder Recipient of the payout.
    /// @param amount Token units sent.
    event Redeemed(address option, address token, address holder, uint256 amount);

    /// @dev Restricts a privileged call to the paired {Option} contract only.
    modifier onlyOption() {
        if (msg.sender != option()) revert UnauthorizedCaller();
        _;
    }

    /// @dev Blocks calls that must happen while the option is still live (e.g. mint).
    modifier notExpired() {
        if (block.timestamp >= expirationDate()) revert ContractExpired();
        _;
    }

    /// @dev Gates the exercise paths. Window closes for everyone at `exerciseDeadline`. For
    ///      European options, the window only *opens* at `expirationDate` — pre-expiry exercise
    ///      reverts with `EuropeanExerciseDisabled`.
    modifier withinExerciseWindow() {
        if (block.timestamp >= exerciseDeadline()) revert ExerciseWindowClosed();
        if (isEuro() && block.timestamp < expirationDate()) revert EuropeanExerciseDisabled();
        _;
    }

    /// @dev Blocks short-side redemption until after the exercise window closes.
    modifier afterExerciseWindow() {
        if (block.timestamp < exerciseDeadline()) revert ExerciseWindowOpen();
        _;
    }

    /// @dev Rejects zero-amount mutations.
    modifier validAmount(uint256 amount) {
        if (amount == 0) revert InvalidValue();
        _;
    }

    /// @dev Rejects the zero address where a real contract is required.
    modifier validAddress(address addr) {
        if (addr == address(0)) revert InvalidAddress();
        _;
    }

    /// @dev Ensures `account` holds at least `amount` of this Receipt token.
    modifier sufficientBalance(address account, uint256 amount) {
        if (balanceOf(account) < amount) revert InsufficientBalance();
        _;
    }

    /// @dev Ensures the contract itself holds at least `amount` of collateral.
    modifier sufficientCollateral(uint256 amount) {
        if (collateral().balanceOf(address(this)) < amount) revert InsufficientCollateral();
        _;
    }

    /// @dev Ensures `account` holds at least `toConsideration(amount)` of consideration.
    modifier sufficientConsideration(address account, uint256 amount) {
        uint256 consAmount = toConsideration(amount);
        if (consideration().balanceOf(account) < consAmount) revert InsufficientConsideration();
        _;
    }

    /// @notice Template constructor. Never called for user-facing instances; clones are produced
    ///         by `ClonesWithImmutableArgs.clone(template, args)` and never delegate the
    ///         constructor. `factory` is captured from the deployer (the Factory that deployed
    ///         the template) so every clone-via-delegatecall reads the same FACTORY immutable.
    constructor(string memory name_, string memory symbol_) ERC20(name_, symbol_) {
        factory = IFactoryTransfer(msg.sender);
    }

    // ============ IMMUTABLE-ARG GETTERS ============

    /// @notice Strike price, 18-decimal fixed point (consideration per collateral; inverted for puts).
    function strike() public pure returns (uint256) {
        return _getArgUint256(0);
    }

    /// @notice Underlying collateral token (e.g. WETH). All collateral sits here.
    function collateral() public pure returns (IERC20) {
        return IERC20(_getArgAddress(32));
    }

    /// @notice Consideration / quote token (e.g. USDC). Accrues here from exercise payments.
    function consideration() public pure returns (IERC20) {
        return IERC20(_getArgAddress(52));
    }

    /// @notice The paired {Option} contract. Only this address can call mint / burn / exercise.
    function option() public pure returns (address) {
        return _getArgAddress(72);
    }

    /// @notice Unix timestamp at which the option expires.
    function expirationDate() public pure returns (uint40) {
        return uint40(_getArgUint64(92));
    }

    /// @notice Unix timestamp at which the post-expiry exercise window closes.
    function exerciseDeadline() public pure returns (uint40) {
        return uint40(_getArgUint64(100));
    }

    /// @notice `true` if put, `false` if call.
    function isPut() public pure returns (bool) {
        return _getArgUint8(108) != 0;
    }

    /// @notice `true` if European-style.
    function isEuro() public pure returns (bool) {
        return _getArgUint8(109) != 0;
    }

    /// @notice Cached `collateral.decimals()` used in conversion math.
    function collDecimals() public pure returns (uint8) {
        return _getArgUint8(110);
    }

    /// @notice Cached `consideration.decimals()` used in conversion math.
    function consDecimals() public pure returns (uint8) {
        return _getArgUint8(111);
    }

    // ============ MINT ============

    /// @notice Mint `amount` Receipt tokens to `account`, pulling the matching amount of
    ///         underlying collateral through the factory's allowance registry.
    /// @dev    Only callable by the paired {Option} contract.
    /// @param account Recipient of the newly-minted Receipt tokens.
    /// @param amount  Collateral-denominated amount.
    function mint(address account, uint256 amount)
        public
        onlyOption
        notExpired
        nonReentrant
        validAmount(amount)
        validAddress(account)
    {
        if (amount > type(uint160).max) revert ArithmeticOverflow();

        IERC20 coll = collateral();
        uint256 balanceBefore = coll.balanceOf(address(this));
        // forge-lint: disable-next-line(unsafe-typecast)
        factory.transferFrom(account, address(this), uint160(amount), address(coll));
        if (coll.balanceOf(address(this)) - balanceBefore < amount) {
            revert FeeOnTransferNotSupported();
        }

        _mint(account, amount);
    }

    // ============ PAIR BURN (called by Option, valid pre-deadline) ============

    /// @notice Burn matched Option + Receipt pair, return collateral. Only callable by Option.
    /// @dev    Available pre-`exerciseDeadline` only. Once the window closes, all short-side
    ///         exits must go through `_redeemProRata` so collateral and consideration are split
    ///         fairly across remaining receipts.
    /// @param account Recipient of the collateral.
    /// @param amount  Amount of Receipt tokens to burn.
    function burn(address account, uint256 amount)
        public
        onlyOption
        nonReentrant
        sufficientBalance(account, amount)
        validAmount(amount)
    {
        if (block.timestamp >= exerciseDeadline()) revert ExerciseWindowClosed();
        IERC20 coll = collateral();
        _burn(account, amount);
        coll.safeTransfer(account, amount);
        emit Redeemed(option(), address(coll), account, amount);
    }

    // ============ EXERCISE ============

    /// @notice Exercise path invoked by Option. `caller` pays consideration; `account` receives collateral.
    /// @param account The collateral recipient (option holder being exercised in favour of).
    /// @param amount  Collateral units to deliver; consideration collected is `ceil(amount * strike)`.
    /// @param caller  The account paying consideration (`msg.sender` at the Option layer).
    function exercise(address account, uint256 amount, address caller)
        public
        withinExerciseWindow
        onlyOption
        nonReentrant
        sufficientCollateral(amount)
        validAmount(amount)
    {
        address this_ = address(this);
        IERC20 cons = consideration();
        IERC20 coll = collateral();
        uint256 consAmount = toNeededConsideration(amount);
        if (cons.balanceOf(caller) < consAmount) revert InsufficientConsideration();
        if (consAmount == 0) revert InvalidValue();
        if (consAmount > type(uint160).max) revert ArithmeticOverflow();

        uint256 consBefore = cons.balanceOf(this_);
        // forge-lint: disable-next-line(unsafe-typecast)
        factory.transferFrom(caller, this_, uint160(consAmount), address(cons));
        if (cons.balanceOf(this_) - consBefore < consAmount) revert FeeOnTransferNotSupported();
        coll.safeTransfer(account, amount);
    }

    // ============ POST-WINDOW REDEEM ============

    /// @notice Redeem the caller's full Receipt balance after the exercise window closes.
    function redeem() public {
        redeem(msg.sender, balanceOf(msg.sender));
    }

    /// @notice Redeem `amount` of the caller's Receipt after the exercise window closes.
    function redeem(uint256 amount) public {
        redeem(msg.sender, amount);
    }

    /// @notice Redeem `amount` for `account` after the exercise window closes (anyone may call).
    function redeem(address account, uint256 amount) public afterExerciseWindow nonReentrant {
        _redeemProRata(account, amount);
    }

    /// @dev Pro-rata payout. Pays `amount` first in collateral up to the available balance, then
    ///      tops up with consideration at the strike rate. Cap on collateralBalance prevents
    ///      donations / positive rebases from underflowing the consideration top-up.
    function _redeemProRata(address account, uint256 amount)
        internal
        sufficientBalance(account, amount)
        validAmount(amount)
    {
        IERC20 coll = collateral();
        uint256 ts = totalSupply();
        uint256 collateralBalance = Math.min(coll.balanceOf(address(this)), ts);
        uint256 collateralToSend = Math.mulDiv(amount, collateralBalance, ts);
        uint256 remainder = amount - collateralToSend;

        _burn(account, amount);

        if (collateralToSend > 0) {
            coll.safeTransfer(account, collateralToSend);
        }
        if (remainder > 0) {
            uint256 consToSend = toConsideration(remainder);
            if (consToSend > 0) consideration().safeTransfer(account, consToSend);
        }
        emit Redeemed(option(), address(coll), account, collateralToSend);
    }

    // ============ REDEEM CONSIDERATION ============

    /// @notice Convert `amount` Receipt tokens straight into consideration at the strike rate.
    function redeemConsideration(uint256 amount) public nonReentrant {
        _redeemConsideration(msg.sender, amount);
    }

    function _redeemConsideration(address account, uint256 collAmount)
        internal
        sufficientBalance(account, collAmount)
        sufficientConsideration(address(this), collAmount)
        validAmount(collAmount)
    {
        IERC20 cons = consideration();
        _burn(account, collAmount);
        uint256 consAmount = toConsideration(collAmount);
        if (consAmount == 0) revert InvalidValue();
        cons.safeTransfer(account, consAmount);
        emit Redeemed(option(), address(cons), account, consAmount);
    }

    // ============ SWEEPS ============

    function sweep(address holder) public afterExerciseWindow nonReentrant {
        uint256 amount = balanceOf(holder);
        if (amount == 0) return;
        _redeemProRata(holder, amount);
    }

    function sweep(address[] calldata holders) public afterExerciseWindow nonReentrant {
        for (uint256 i = 0; i < holders.length; i++) {
            address holder = holders[i];
            uint256 bal = balanceOf(holder);
            if (bal == 0) continue;
            _redeemProRata(holder, bal);
        }
    }

    // ============ CONVERSIONS ============

    function toConsideration(uint256 amount) public pure returns (uint256) {
        return Math.mulDiv(amount, strike() * (10 ** consDecimals()), (10 ** STRIKE_DECIMALS) * (10 ** collDecimals()));
    }

    function toNeededConsideration(uint256 amount) public pure returns (uint256) {
        return Math.mulDiv(
            amount,
            strike() * (10 ** consDecimals()),
            (10 ** STRIKE_DECIMALS) * (10 ** collDecimals()),
            Math.Rounding.Ceil
        );
    }

    function toCollateral(uint256 consAmount) public pure returns (uint256) {
        return
            Math.mulDiv(consAmount, (10 ** collDecimals()) * (10 ** STRIKE_DECIMALS), strike() * (10 ** consDecimals()));
    }

    // ============ METADATA ============

    function name() public view override returns (string memory) {
        uint256 displayStrike = isPut() ? (1e36 / strike()) : strike();
        return string(
            abi.encodePacked(
                isEuro() ? "RCTE-" : "RCT-",
                IERC20Metadata(address(collateral())).symbol(),
                "-",
                IERC20Metadata(address(consideration())).symbol(),
                "-",
                OptionUtils.strike2str(displayStrike),
                "-",
                OptionUtils.epoch2str(expirationDate())
            )
        );
    }

    function symbol() public view override returns (string memory) {
        return name();
    }

    function decimals() public view override returns (uint8) {
        return collDecimals();
    }

    function collateralData() public view returns (TokenData memory) {
        IERC20 coll = collateral();
        IERC20Metadata m = IERC20Metadata(address(coll));
        return TokenData({ address_: address(coll), name: m.name(), symbol: m.symbol(), decimals: m.decimals() });
    }

    function considerationData() public view returns (TokenData memory) {
        IERC20 cons = consideration();
        IERC20Metadata m = IERC20Metadata(address(cons));
        return TokenData({ address_: address(cons), name: m.name(), symbol: m.symbol(), decimals: m.decimals() });
    }
}
