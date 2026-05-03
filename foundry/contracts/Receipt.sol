// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { ReentrancyGuardTransient } from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";
import { IERC20, ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

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
 *         The holder decides off-chain whether the option is ITM and pays strike to exercise; the
 *         protocol just enforces timing and the 1:1 collateral invariant.
 *
 *         Pair-redeem (`burn`, called by Option) stays available the entire lifetime —
 *         it doesn't depend on the window because it burns matched long+short pairs.
 *
 *         ### Rounding
 *
 *         - Collections from users (exercise): round UP (`toNeededConsideration`).
 *         - Payouts to users (redeem): round DOWN (floor).
 *
 *         Dust stays in the contract, guaranteeing the key invariant
 *         `available_collateral >= outstanding_option_supply` at every state transition.
 *
 * @dev    Deployed once as a template; per-option instances are EIP-1167 minimal proxy clones.
 *         `init()` is used instead of a constructor. Owner of each clone is its paired
 *         {Option} contract — only Option can drive mint / exercise / pair-redeem.
 */
contract Receipt is ERC20, Ownable, ReentrancyGuardTransient {
    /// @dev Storage layout — packed into 4 slots (was 5 + OZ Initializable's flag):
    ///      slot 0: strike (32)
    ///      slot 1: collateral (20) + locked (1) + consDecimals (1) + collDecimals (1)
    ///      slot 2: consideration (20)
    ///      slot 3: factory (20) + expirationDate (5) + exerciseDeadline (5) + isPut (1) + isEuro (1)
    /// @notice Strike price, 18-decimal fixed point, "consideration per collateral".
    /// @dev For puts this is the *inverted* human strike (see {Option} `name()` for display).
    uint256 public strike;

    /// @notice Underlying collateral token (e.g. WETH). All collateral sits here.
    IERC20 public collateral;
    /// @notice Owner-controlled emergency pause flag.
    bool public locked;
    /// @notice Cached `consideration.decimals()` used in conversion math.
    uint8 public consDecimals;
    /// @notice Cached `collateral.decimals()` used in conversion math.
    uint8 public collDecimals;

    /// @notice Consideration / quote token (e.g. USDC). Accrues here from exercise payments.
    IERC20 public consideration;

    /// @notice Factory that created this option, used to pull tokens through its Permit2-style
    ///         allowance registry. Doubles as the init guard — non-zero means initialised.
    IFactoryTransfer public factory;

    /// @notice Unix timestamp at which the option expires.
    uint40 public expirationDate;
    /// @notice Unix timestamp at which the post-expiry exercise window closes. Set to
    ///         `expirationDate + windowSeconds` in {init}.
    uint40 public exerciseDeadline;
    /// @notice `true` if put, `false` if call.
    bool public isPut;
    /// @notice `true` if European-style: exercise is barred pre-expiry and only allowed within the
    ///         post-expiry window. `false` for American-style: exercise allowed pre-expiry too.
    bool public isEuro;

    /// @notice Decimal basis of the strike — fixed at 18 and independent of token decimals.
    uint8 public constant STRIKE_DECIMALS = 18;

    /// @notice Thrown when a pre-expiry-only path (mint) runs after expiration.
    error ContractNotExpired();
    /// @notice Thrown when a post-expiry-only path runs before expiration.
    error ContractExpired();
    /// @notice Thrown when an account does not hold enough Receipt tokens for the operation.
    error InsufficientBalance();
    /// @notice Thrown on `amount == 0` (or any derived zero-amount the invariant requires to be positive).
    error InvalidValue();
    /// @notice Thrown when a zero address is supplied where a real token/contract is required.
    error InvalidAddress();
    /// @notice Thrown when the option has been paused by its owner.
    error LockedContract();
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
    /// @notice Thrown when {init} is called on a clone that has already been initialised, or on
    ///         the template (whose `factory` is set to a sentinel by the constructor).
    error AlreadyInitialized();

    /// @notice Emitted on every path that returns collateral or consideration to a user.
    /// @param option The paired Option contract (also this contract's owner).
    /// @param token  The token actually transferred out (`collateral` or `consideration`).
    /// @param holder Recipient of the payout.
    /// @param amount Token units sent.
    event Redeemed(address option, address token, address holder, uint256 amount);

    /// @dev Blocks calls that must happen while the option is still live (e.g. mint).
    modifier notExpired() {
        if (block.timestamp >= expirationDate) revert ContractExpired();
        _;
    }

    /// @dev Gates the exercise paths. Window closes for everyone at `exerciseDeadline`. For
    ///      European options, the window only *opens* at `expirationDate` — pre-expiry exercise
    ///      reverts with `EuropeanExerciseDisabled`.
    modifier withinExerciseWindow() {
        if (block.timestamp >= exerciseDeadline) revert ExerciseWindowClosed();
        if (isEuro && block.timestamp < expirationDate) revert EuropeanExerciseDisabled();
        _;
    }

    /// @dev Blocks short-side redemption until after the exercise window closes.
    modifier afterExerciseWindow() {
        if (block.timestamp < exerciseDeadline) revert ExerciseWindowOpen();
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

    /// @dev Blocks mutations while the owner has paused the option.
    modifier notLocked() {
        if (locked) revert LockedContract();
        _;
    }

    /// @dev Ensures the contract itself holds at least `amount` of collateral.
    modifier sufficientCollateral(uint256 amount) {
        if (collateral.balanceOf(address(this)) < amount) revert InsufficientCollateral();
        _;
    }

    /// @dev Ensures `account` holds at least `toConsideration(amount)` of consideration.
    modifier sufficientConsideration(address account, uint256 amount) {
        uint256 consAmount = toConsideration(amount);
        if (consideration.balanceOf(account) < consAmount) revert InsufficientConsideration();
        _;
    }

    /// @notice Template constructor. Never called for user-facing instances; each clone goes
    ///         through {init} instead. Sets `factory` to a non-zero sentinel so the template
    ///         itself fails the {init} guard.
    constructor(string memory name_, string memory symbol_) ERC20(name_, symbol_) Ownable(msg.sender) {
        factory = IFactoryTransfer(address(0xdead));
    }

    /// @notice Initialises a freshly-cloned Receipt. Called exactly once by the factory.
    /// @param collateral_    Underlying collateral token.
    /// @param consideration_ Quote / consideration token.
    /// @param expirationDate_ Unix timestamp at which the option expires; must be in the future.
    /// @param strike_        Strike price in 18-decimal fixed point (consideration per collateral).
    /// @param isPut_         True if put, false if call.
    /// @param isEuro_        True for European (exercise only post-expiry within the window), false
    ///                       for American (exercise any time before `exerciseDeadline`).
    /// @param windowSeconds_ Length of the post-expiry exercise window in seconds.
    /// @param option_        Paired {Option} contract — becomes this Receipt's owner.
    /// @param factory_       {Factory} used as the centralised allowance / transfer authority.
    function init(
        address collateral_,
        address consideration_,
        uint40 expirationDate_,
        uint256 strike_,
        bool isPut_,
        bool isEuro_,
        uint40 windowSeconds_,
        address option_,
        address factory_
    ) public {
        if (address(factory) != address(0)) revert AlreadyInitialized();
        if (collateral_ == address(0)) revert InvalidAddress();
        if (consideration_ == address(0)) revert InvalidAddress();
        if (factory_ == address(0)) revert InvalidAddress();
        if (option_ == address(0)) revert InvalidAddress();
        if (strike_ == 0) revert InvalidValue();
        if (expirationDate_ < block.timestamp) revert InvalidValue();
        if (isEuro_ && windowSeconds_ == 0) revert InvalidValue();

        collateral = IERC20(collateral_);
        consideration = IERC20(consideration_);
        expirationDate = expirationDate_;
        exerciseDeadline = expirationDate_ + windowSeconds_;
        strike = strike_;
        isPut = isPut_;
        isEuro = isEuro_;
        factory = IFactoryTransfer(factory_);
        consDecimals = IERC20Metadata(consideration_).decimals();
        collDecimals = IERC20Metadata(collateral_).decimals();
        _transferOwnership(option_);
    }

    // ============ MINT ============

    /// @notice Mint `amount` Receipt tokens to `account`, pulling the matching amount of
    ///         underlying collateral through the factory's allowance registry.
    /// @dev    Only callable by the paired {Option} contract (the owner). `amount` is capped at
    ///         `uint160.max` because the factory's transfer path uses Permit2-compatible typing.
    ///         Fee-on-transfer tokens are detected and rejected (balance-diff check).
    /// @param account Recipient of the newly-minted Receipt tokens.
    /// @param amount  Collateral-denominated amount (same decimals as the collateral token).
    function mint(address account, uint256 amount)
        public
        onlyOwner
        notExpired
        notLocked
        nonReentrant
        validAmount(amount)
        validAddress(account)
    {
        if (amount > type(uint160).max) revert ArithmeticOverflow();

        uint256 balanceBefore = collateral.balanceOf(address(this));
        // forge-lint: disable-next-line(unsafe-typecast)
        factory.transferFrom(account, address(this), uint160(amount), address(collateral));
        if (collateral.balanceOf(address(this)) - balanceBefore != amount) {
            revert FeeOnTransferNotSupported();
        }

        _mint(account, amount);
    }

    // ============ PAIR BURN (called by Option, valid the entire lifetime) ============

    /// @notice Burn matched Option + Receipt pair, return collateral. Only callable by Option.
    /// @dev    Available the entire option lifetime — pair redemption doesn't depend on the
    ///         exercise window because both long and short are burned in equal amount.
    ///         Falls back to a consideration payout if the contract is under-collateralized at
    ///         the collateral layer (defense-in-depth).
    /// @param account Recipient of the collateral.
    /// @param amount  Amount of Receipt tokens to burn.
    function burn(address account, uint256 amount)
        public
        notLocked
        onlyOwner
        nonReentrant
        sufficientBalance(account, amount)
        validAmount(amount)
    {
        if (block.timestamp >= exerciseDeadline) revert ExerciseWindowClosed();
        // Pair burn: caller already proved `Option.balanceOf >= amount` at the Option layer, and
        // the global invariant `collateral.balanceOf(this) == Option.totalSupply()` guarantees
        // enough collateral is on hand.
        _burn(account, amount);
        collateral.safeTransfer(account, amount);
        emit Redeemed(address(owner()), address(collateral), account, amount);
    }

    // ============ EXERCISE ============

    /// @notice Exercise path invoked by Option. `caller` pays consideration; `account` receives collateral.
    /// @dev    Only callable by the paired Option. Allowed pre-expiry and within the post-expiry
    ///         exercise window (`block.timestamp < exerciseDeadline`). Consideration amount is
    ///         computed with `toNeededConsideration` (ceiling-rounded — favours the protocol on
    ///         collection).
    /// @param account The collateral recipient (option holder being exercised in favour of).
    /// @param amount  Collateral units to deliver; consideration collected is `ceil(amount * strike)`.
    /// @param caller  The account paying consideration (`msg.sender` at the Option layer).
    function exercise(address account, uint256 amount, address caller)
        public
        withinExerciseWindow
        notLocked
        onlyOwner
        nonReentrant
        sufficientCollateral(amount)
        validAmount(amount)
    {
        address this_ = address(this);
        uint256 consAmount = toNeededConsideration(amount);
        if (consideration.balanceOf(caller) < consAmount) revert InsufficientConsideration();
        if (consAmount == 0) revert InvalidValue();
        if (consAmount > type(uint160).max) revert ArithmeticOverflow();

        uint256 consBefore = consideration.balanceOf(this_);
        // forge-lint: disable-next-line(unsafe-typecast)
        factory.transferFrom(caller, this_, uint160(consAmount), address(consideration));
        if (consideration.balanceOf(this_) - consBefore < consAmount) revert FeeOnTransferNotSupported();
        collateral.safeTransfer(account, amount);
    }

    // ============ POST-WINDOW REDEEM ============

    /// @notice Redeem the caller's full Receipt balance after the exercise window closes.
    ///         Pro-rata over `(collateral, consideration)` held by this contract.
    function redeem() public notLocked {
        redeem(msg.sender, balanceOf(msg.sender));
    }

    /// @notice Redeem `amount` of the caller's Receipt after the exercise window closes.
    /// @param amount Receipt tokens to burn.
    function redeem(uint256 amount) public notLocked {
        redeem(msg.sender, amount);
    }

    /// @notice Redeem `amount` for `account` after the exercise window closes (anyone may call —
    ///         used by keepers to sweep short-side holders).
    /// @param account The Receipt holder whose position is redeemed.
    /// @param amount  Amount of Receipt tokens to burn.
    function redeem(address account, uint256 amount) public afterExerciseWindow notLocked nonReentrant {
        _redeemProRata(account, amount);
    }

    /// @dev Pro-rata payout. Pays `amount` first in collateral up to the available balance, then
    ///      tops up with consideration at the strike rate.
    function _redeemProRata(address account, uint256 amount)
        internal
        sufficientBalance(account, amount)
        validAmount(amount)
    {
        uint256 ts = totalSupply();
        // Cap balance at totalSupply so donations / positive rebases can't push
        // collateralToSend above amount and underflow the consideration top-up.
        uint256 collateralBalance = Math.min(collateral.balanceOf(address(this)), ts);
        uint256 collateralToSend = Math.mulDiv(amount, collateralBalance, ts);
        uint256 remainder = amount - collateralToSend;

        _burn(account, amount);

        if (collateralToSend > 0) {
            collateral.safeTransfer(account, collateralToSend);
        }
        if (remainder > 0) {
            uint256 consToSend = toConsideration(remainder);
            if (consToSend > 0) consideration.safeTransfer(account, consToSend);
        }
        emit Redeemed(address(owner()), address(collateral), account, collateralToSend);
    }

    // ============ REDEEM CONSIDERATION ============

    /// @notice Convert `amount` Receipt tokens straight into consideration at the strike rate.
    /// @dev    Useful for a short-side holder who wants their payout settled in quote currency
    ///         rather than a mix of collateral and consideration.
    /// @param amount Receipt tokens to burn.
    function redeemConsideration(uint256 amount) public notLocked nonReentrant {
        _redeemConsideration(msg.sender, amount);
    }

    /// @dev Shared body for direct `redeemConsideration` calls and the pair-redeem fallback.
    function _redeemConsideration(address account, uint256 collAmount)
        internal
        sufficientBalance(account, collAmount)
        sufficientConsideration(address(this), collAmount)
        validAmount(collAmount)
    {
        _burn(account, collAmount);
        uint256 consAmount = toConsideration(collAmount);
        if (consAmount == 0) revert InvalidValue();
        consideration.safeTransfer(account, consAmount);
        emit Redeemed(address(owner()), address(consideration), account, consAmount);
    }

    // ============ SWEEPS ============

    /// @notice Redeem `holder`'s full Receipt balance after the exercise window closes.
    ///         No-op for zero-balance accounts. Useful for gas-sponsored cleanup.
    /// @param holder The short-side holder to sweep.
    function sweep(address holder) public afterExerciseWindow notLocked nonReentrant {
        uint256 amount = balanceOf(holder);
        if (amount == 0) return;
        _redeemProRata(holder, amount);
    }

    /// @notice Batch form of {sweep}.
    /// @param holders Array of short-side holders to sweep.
    function sweep(address[] calldata holders) public afterExerciseWindow notLocked nonReentrant {
        for (uint256 i = 0; i < holders.length; i++) {
            address holder = holders[i];
            uint256 bal = balanceOf(holder);
            if (bal == 0) continue;
            _redeemProRata(holder, bal);
        }
    }

    // ============ ADMIN ============

    /// @notice Emergency pause. Blocks all user-facing mutations on this contract and its Option.
    /// @dev    Only callable by the owner (the paired Option, which gates its own `lock()` on Ownable).
    function lock() public onlyOwner {
        locked = true;
    }

    /// @notice Resume after a {lock}.
    function unlock() public onlyOwner {
        locked = false;
    }

    // ============ CONVERSIONS ============

    /// @notice Convert a collateral amount to the consideration it is worth at the strike rate,
    ///         normalised for both tokens' decimals. Floor-rounded — used for payouts.
    /// @dev    Formula: `amount * strike * 10^consDec / (10^18 * 10^collDec)`.
    /// @param amount Collateral-denominated amount (same decimals as the collateral token).
    /// @return Consideration amount in the consideration token's native decimals.
    function toConsideration(uint256 amount) public view returns (uint256) {
        return Math.mulDiv(amount, strike * (10 ** consDecimals), (10 ** STRIKE_DECIMALS) * (10 ** collDecimals));
    }

    /// @notice Same as {toConsideration} but ceiling-rounded — used when *collecting* consideration
    ///         so the protocol never accepts a short payment.
    /// @param amount Collateral-denominated amount.
    /// @return Ceiling-rounded consideration required.
    function toNeededConsideration(uint256 amount) public view returns (uint256) {
        return Math.mulDiv(
            amount, strike * (10 ** consDecimals), (10 ** STRIKE_DECIMALS) * (10 ** collDecimals), Math.Rounding.Ceil
        );
    }

    /// @notice Inverse of {toConsideration} — how much collateral a given consideration amount is worth
    ///         at the strike rate.
    /// @param consAmount Consideration-denominated amount.
    /// @return Collateral-denominated amount (floor-rounded).
    function toCollateral(uint256 consAmount) public view returns (uint256) {
        return Math.mulDiv(consAmount, (10 ** collDecimals) * (10 ** STRIKE_DECIMALS), strike * (10 ** consDecimals));
    }

    // ============ METADATA ============

    /// @notice Human-readable token name, mirroring {Option} but with a `RCT[E]-` prefix.
    ///         Puts display the inverted strike back in human form (`1e36 / strike`).
    function name() public view override returns (string memory) {
        uint256 displayStrike = isPut ? (1e36 / strike) : strike;
        return string(
            abi.encodePacked(
                isEuro ? "RCTE-" : "RCT-",
                IERC20Metadata(address(collateral)).symbol(),
                "-",
                IERC20Metadata(address(consideration)).symbol(),
                "-",
                OptionUtils.strike2str(displayStrike),
                "-",
                OptionUtils.epoch2str(expirationDate)
            )
        );
    }

    /// @notice Same as {name}. Keeping them aligned avoids wallet/explorer drift.
    function symbol() public view override returns (string memory) {
        return name();
    }

    /// @notice Decimals match the underlying collateral so 1 Receipt unit ↔ 1 collateral unit.
    function decimals() public view override returns (uint8) {
        return collDecimals;
    }

    /// @notice Metadata bundle for the collateral token (convenience read).
    function collateralData() public view returns (TokenData memory) {
        IERC20Metadata m = IERC20Metadata(address(collateral));
        return TokenData({ address_: address(collateral), name: m.name(), symbol: m.symbol(), decimals: m.decimals() });
    }

    /// @notice Metadata bundle for the consideration token (convenience read).
    function considerationData() public view returns (TokenData memory) {
        IERC20Metadata m = IERC20Metadata(address(consideration));
        return
            TokenData({ address_: address(consideration), name: m.name(), symbol: m.symbol(), decimals: m.decimals() });
    }

    /// @notice Paired Option contract (also this Receipt's owner).
    function option() public view returns (address) {
        return owner();
    }
}
