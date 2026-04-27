// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { Initializable } from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import { ReentrancyGuardTransient } from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";
import { IERC20, ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

using SafeERC20 for IERC20;

import { TokenData } from "./interfaces/IOption.sol";
import { OptionUtils } from "./OptionUtils.sol";
import { IPriceOracle } from "./oracles/IPriceOracle.sol";
import { ISettlementSwapper } from "./interfaces/ISettlementSwapper.sol";

/// @dev Narrow view of {Factory} used by {Collateral} to pull collateral/consideration tokens via the
///      factory's centralised allowance registry.
interface IFactoryTransfer {
    function transferFrom(address from, address to, uint160 amount, address token) external;
}

/**
 * @title  Collateral — short-side ERC20
 * @author Greek.fi
 * @notice The short side of a Greek option pair. Holding this token means you have *sold* the
 *         option: you received the premium (off-chain) and now bear the obligation of the
 *         exercise / settlement payoff. It holds all collateral for the pair and receives the
 *         consideration paid on exercise.
 *
 *         Three settlement modes are chosen at creation and reflected in `(oracle, isEuro)`:
 *
 *         | Mode                 | `oracle` | `isEuro` | Pre-expiry path  | Post-expiry paths                         |
 *         | -------------------- | -------- | -------- | ---------------- | ----------------------------------------- |
 *         | American non-settled | `0`      | `false`  | pair redeem +    | pro-rata `redeem` over `(coll, cons)`     |
 *         |                      |          |          | `exercise`       | + `redeemConsideration`                   |
 *         | American settled     | set      | `false`  | pair redeem +    | oracle-settled `redeem`;                  |
 *         |                      |          |          | `exercise`       | option-holder `claim` via Option.sol      |
 *         | European             | set      | `true`   | pair redeem only | oracle-settled `redeem`;                  |
 *         |                      |          |          | (no exercise)    | option-holder `claim` via Option.sol      |
 *
 *         `(oracle == 0 && isEuro)` is rejected at the factory — European options always need a price.
 *
 *         ### Post-expiry in settled modes
 *
 *         On first {settle} call after expiration, the oracle price `S` is latched. If the option
 *         finishes ITM (`S > K`) we reserve a portion of the collateral — `optionReserveRemaining` —
 *         for option holders to claim the `(S-K)/S` residual. Remaining collateral plus any
 *         consideration earned during pre-expiry exercise is paid pro-rata to short-side holders
 *         via {redeem} / {sweep}.
 *
 *         ### Rounding
 *
 *         - Collections from users (exercise): round UP (`toNeededConsideration`).
 *         - Payouts to users (redeem, claim): round DOWN (floor).
 *
 *         Dust stays in the contract, guaranteeing the key invariant
 *         `available_collateral >= outstanding_option_supply` at every state transition.
 *
 * @dev    Deployed once as a template; per-option instances are EIP-1167 minimal proxy clones.
 *         `init()` is used instead of a constructor. Owner of each clone is its paired
 *         {Option} contract — only Option can drive mint / exercise / pair-redeem.
 */
contract Collateral is ERC20, Ownable, ReentrancyGuardTransient, Initializable {
    /// @notice Strike price, 18-decimal fixed point, "consideration per collateral".
    /// @dev For puts this is the *inverted* human strike (see {Option} `name()` for display).
    uint256 public strike;

    /// @notice Oracle spot price latched on first post-expiry settle. 0 until settled.
    /// @dev 18-decimal fixed point; same encoding as {strike}.
    uint256 public settlementPrice;

    /// @notice Collateral reserved for option-holder ITM claims. Decremented on each `_claimForOption`.
    /// @dev Initialised to `O * (S-K) / S` the first time `settle` runs post-expiry (zero if OTM).
    uint256 public optionReserveRemaining;

    /// @notice Underlying collateral token (e.g. WETH). All collateral sits here.
    IERC20 public collateral;

    /// @notice Consideration / quote token (e.g. USDC). Accrues here from exercise payments.
    IERC20 public consideration;

    /// @dev Factory handle used to pull tokens through its centralised allowance registry.
    IFactoryTransfer public _factory;

    /// @notice Settlement oracle. `address(0)` in American non-settled mode.
    IPriceOracle public oracle;

    /// @notice Unix timestamp at which the option expires.
    uint40 public expirationDate;
    /// @notice `true` if put, `false` if call.
    bool public isPut;
    /// @notice `true` if European-style (no pre-expiry exercise).
    bool public isEuro;
    /// @notice Owner-controlled emergency pause flag.
    bool public locked;
    /// @notice Cached `consideration.decimals()` used in conversion math.
    uint8 public consDecimals;
    /// @notice Cached `collateral.decimals()` used in conversion math.
    uint8 public collDecimals;
    /// @notice `true` once the first post-expiry settle has initialised `optionReserveRemaining`.
    bool public reserveInitialized;
    /// @notice Latched at first {settle}: `true` if the option settled ITM (`S > K` for calls,
    ///         `S < K` for puts). Read by `exerciseFor` as the ITM gate — no per-call recomputation.
    bool public isItmAtSettle;

    // ============ SETTLEMENT ASSET (opt-in per holder) ============
    //
    // Default post-expiry settlement is consideration (cash): when anyone triggers
    // {convertResidualToConsideration}, the contract swaps the full ITM reserve into
    // consideration at market via a caller-supplied {ISettlementSwapper}, and every
    // `claim` by default pays consideration. A holder who wants in-kind collateral
    // instead calls {requestCollateral} post-expiry — their balance is locked into the
    // collateral pool and that slice is NOT swapped. {Option.claim} reads the flag and
    // pays WETH (collateral opt-ins) or USDC (default) automatically.

    /// @notice Holder-chosen settlement asset. `false` (default) = consideration/cash.
    ///         `true` = collateral/in-kind. Flippable until the swap completes.
    mapping(address => bool) public wantsCollateral;
    /// @notice Option balance locked in the collateral (in-kind) pool when a holder
    ///         flips {wantsCollateral} to `true`. Snapshot at flag-flip time; decremented
    ///         as the holder claims in-kind.
    mapping(address => uint256) internal _collateralLocked;
    /// @notice Sum of {_collateralLocked}. Cash-pool WETH to swap =
    ///         `(totalSupply − totalCollateralReservedOptions) × (S−K) / S`.
    uint256 public totalCollateralReservedOptions;
    /// @notice `true` once {convertResidualToConsideration} has run. One-shot.
    bool public cashSwapCompleted;
    /// @notice Consideration paid per option unit claimed in cash (1e18-scaled WAD). Latched at swap.
    uint256 public cashConsiderationPerOptionWad;

    /// @notice Decimal basis of the strike — fixed at 18 and independent of token decimals.
    uint8 public constant STRIKE_DECIMALS = 18;

    /// @notice Thrown when a pre-expiry-only path (mint, exercise, pair-redeem) runs after expiration.
    error ContractNotExpired();
    /// @notice Thrown when a post-expiry-only path (redeem, sweep, claim) runs before expiration.
    error ContractExpired();
    /// @notice Thrown when an account does not hold enough Collateral tokens for the operation.
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
    /// @notice Thrown when a settled-mode path is invoked on an option with no oracle.
    error NoOracle();
    /// @notice Thrown when a read relies on a settlement price that hasn't been latched yet.
    error NotSettled();
    /// @notice Thrown when a settled-only path is invoked in non-settled mode.
    error SettledOnly();
    /// @notice Thrown when a non-settled-only path is invoked in settled mode.
    error NonSettledOnly();
    /// @notice Thrown when `exercise` is called on a European option.
    error EuropeanExerciseDisabled();
    /// @notice Thrown by `_exerciseForPostExpiry` when the settled price is not ITM.
    error NotITM();
    /// @notice Thrown when a cash-settlement path runs before {convertResidualToConsideration}.
    error CashSwapNotCompleted();
    /// @notice Thrown when {convertResidualToConsideration} is called twice.
    error CashSwapAlreadyCompleted();
    /// @notice Thrown when a holder's cash-reservation action exceeds their option balance.
    error ExceedsBalance();
    /// @notice Thrown when the swapper returns less consideration than `minOut`.
    error SwapSlippage();

    /// @notice Emitted on every path that returns collateral or consideration to a user.
    /// @param option The paired Option contract (also this contract's owner).
    /// @param token  The token actually transferred out (`collateral` or `consideration`).
    /// @param holder Recipient of the payout.
    /// @param amount Token units sent.
    event Redeemed(address option, address token, address holder, uint256 amount);

    /// @notice Emitted once when the oracle price is latched.
    /// @param price 18-decimal settlement price (consideration per collateral).
    event Settled(uint256 price);

    /// @dev Blocks calls that must wait until expiration (e.g. post-expiry redeem).
    modifier expired() {
        if (block.timestamp < expirationDate) revert ContractNotExpired();
        _;
    }

    /// @dev Blocks calls that must happen while the option is still live (e.g. mint, exercise).
    modifier notExpired() {
        if (block.timestamp >= expirationDate) revert ContractExpired();
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

    /// @dev Ensures `account` holds at least `amount` of this Collateral token.
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
    ///         through {init} instead. Disables initializers on the template.
    constructor(string memory name_, string memory symbol_) ERC20(name_, symbol_) Ownable(msg.sender) {
        _disableInitializers();
    }

    /// @notice Initialises a freshly-cloned Collateral. Called exactly once by the factory.
    /// @param collateral_    Underlying collateral token.
    /// @param consideration_ Quote / consideration token.
    /// @param expirationDate_ Unix timestamp at which the option expires; must be in the future.
    /// @param strike_        Strike price in 18-decimal fixed point (consideration per collateral).
    /// @param isPut_         True if put, false if call.
    /// @param isEuro_        True if European-style (exercise disabled, oracle required).
    /// @param oracle_        Settlement oracle; `address(0)` only valid in American non-settled mode.
    /// @param option_        Paired {Option} contract — becomes this Collateral's owner.
    /// @param factory_       {Factory} used as the centralised allowance / transfer authority.
    function init(
        address collateral_,
        address consideration_,
        uint40 expirationDate_,
        uint256 strike_,
        bool isPut_,
        bool isEuro_,
        address oracle_,
        address option_,
        address factory_
    ) public initializer {
        if (collateral_ == address(0)) revert InvalidAddress();
        if (consideration_ == address(0)) revert InvalidAddress();
        if (factory_ == address(0)) revert InvalidAddress();
        if (option_ == address(0)) revert InvalidAddress();
        if (strike_ == 0) revert InvalidValue();
        if (expirationDate_ < block.timestamp) revert InvalidValue();

        collateral = IERC20(collateral_);
        consideration = IERC20(consideration_);
        expirationDate = expirationDate_;
        strike = strike_;
        isPut = isPut_;
        isEuro = isEuro_;
        _factory = IFactoryTransfer(factory_);
        oracle = IPriceOracle(oracle_); // may be zero
        consDecimals = IERC20Metadata(consideration_).decimals();
        collDecimals = IERC20Metadata(collateral_).decimals();
        _transferOwnership(option_);
    }

    // ============ MINT ============

    /// @notice Mint `amount` Collateral tokens to `account`, pulling the matching amount of
    ///         underlying collateral through the factory's allowance registry.
    /// @dev    Only callable by the paired {Option} contract (the owner). `amount` is capped at
    ///         `uint160.max` because the factory's transfer path uses Permit2-compatible typing.
    ///         Fee-on-transfer tokens are detected and rejected (balance-diff check).
    /// @param account Recipient of the newly-minted Collateral tokens.
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
        _factory.transferFrom(account, address(this), uint160(amount), address(collateral));
        if (collateral.balanceOf(address(this)) - balanceBefore != amount) {
            revert FeeOnTransferNotSupported();
        }

        _mint(account, amount);
    }

    // ============ PRE-EXPIRY PAIR REDEEM (called by Option) ============

    /// @notice Burn matched Option + Collateral pair, return collateral. Only callable by Option.
    /// @dev    Falls back to a consideration payout if the contract is under-collateralized at the
    ///         collateral layer (defense-in-depth — this should not happen with the current invariants).
    /// @param account Recipient of the collateral.
    /// @param amount  Amount of Collateral tokens to burn.
    function _redeemPair(address account, uint256 amount) public notExpired notLocked onlyOwner nonReentrant {
        _redeemPairInternal(account, amount);
    }

    /// @dev Waterfall used by both `_redeemPair` and exercise-path fallback.
    function _redeemPairInternal(address account, uint256 amount)
        internal
        sufficientBalance(account, amount)
        validAmount(amount)
    {
        // Waterfall: collateral first, consideration fallback (defense-in-depth).
        uint256 balance = collateral.balanceOf(address(this));
        uint256 collateralToSend = amount <= balance ? amount : balance;

        _burn(account, collateralToSend);

        if (balance < amount) {
            _redeemConsideration(account, amount - balance);
        }

        if (collateralToSend > 0) {
            collateral.safeTransfer(account, collateralToSend);
        }
        emit Redeemed(address(owner()), address(collateral), account, collateralToSend);
    }

    // ============ EXERCISE (American only) ============

    /// @notice Exercise path invoked by Option. `caller` pays consideration; `account` receives collateral.
    /// @dev    Only callable by the paired Option. Consideration amount is computed with
    ///         `toNeededConsideration` (ceiling-rounded — favours the protocol on collection).
    /// @param account The collateral recipient (option holder being exercised in favour of).
    /// @param amount  Collateral units to deliver; consideration collected is `ceil(amount * strike)`.
    /// @param caller  The account paying consideration (`msg.sender` at the Option layer).
    function exercise(address account, uint256 amount, address caller)
        public
        notExpired
        notLocked
        onlyOwner
        nonReentrant
        sufficientCollateral(amount)
        validAmount(amount)
    {
        if (isEuro) revert EuropeanExerciseDisabled();

        uint256 consAmount = toNeededConsideration(amount);
        if (consideration.balanceOf(caller) < consAmount) revert InsufficientConsideration();
        if (consAmount == 0) revert InvalidValue();
        if (consAmount > type(uint160).max) revert ArithmeticOverflow();

        uint256 consBefore = consideration.balanceOf(address(this));
        // forge-lint: disable-next-line(unsafe-typecast)
        _factory.transferFrom(caller, address(this), uint160(consAmount), address(consideration));
        if (consideration.balanceOf(address(this)) - consBefore < consAmount) revert FeeOnTransferNotSupported();
        collateral.safeTransfer(account, amount);
    }

    // ============ POST-EXPIRY REDEEM ============

    /// @notice Redeem the caller's full Collateral balance post-expiry.
    ///         In non-settled mode: pro-rata over `(collateral, consideration)`.
    ///         In settled mode: pro-rata over `(collateral - reserve, consideration)`.
    ///
    /// Example:
    /// ```solidity
    /// // Post-expiry short-side exit (non-settled):
    /// coll.redeem();   // burns all caller's CLL-*, returns collateral + any consideration collected
    /// ```
    function redeem() public notLocked {
        redeem(msg.sender, balanceOf(msg.sender));
    }

    /// @notice Redeem `amount` of the caller's Collateral tokens post-expiry.
    /// @param amount Collateral tokens to burn.
    function redeem(uint256 amount) public notLocked {
        redeem(msg.sender, amount);
    }

    /// @notice Redeem `amount` for `account` post-expiry. Routes to settled or pro-rata path
    ///         based on whether an oracle is configured.
    /// @dev    Callable by anyone — used by keepers to sweep short-side holders.
    /// @param account The Collateral holder whose position is redeemed.
    /// @param amount  Amount of Collateral tokens to burn.
    function redeem(address account, uint256 amount) public expired notLocked nonReentrant {
        if (address(oracle) != address(0)) {
            _settle("");
            _redeemSettled(account, amount);
        } else {
            _redeemProRata(account, amount);
        }
    }

    /// @dev Pro-rata payout used in American non-settled mode. Pays `amount` first in collateral
    ///      up to the available balance, then tops up with consideration at the strike rate.
    function _redeemProRata(address account, uint256 amount)
        internal
        sufficientBalance(account, amount)
        validAmount(amount)
    {
        uint256 ts = totalSupply();
        uint256 collateralBalance = collateral.balanceOf(address(this));
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

    /// @dev Settled-mode payout. Distributes `(collBalance - reserve, consBalance)` pro-rata;
    ///      the reserve stays behind for option-holder `claim`s.
    function _redeemSettled(address account, uint256 amount)
        internal
        sufficientBalance(account, amount)
        validAmount(amount)
    {
        uint256 ts = totalSupply();
        uint256 collBalance = collateral.balanceOf(address(this));
        uint256 reserve = optionReserveRemaining;
        uint256 availableColl = collBalance > reserve ? collBalance - reserve : 0;
        uint256 collToSend = Math.mulDiv(amount, availableColl, ts);
        uint256 consBalance = consideration.balanceOf(address(this));
        uint256 consToSend = consBalance > 0 ? Math.mulDiv(amount, consBalance, ts) : 0;

        _burn(account, amount);
        if (collToSend > 0) collateral.safeTransfer(account, collToSend);
        if (consToSend > 0) consideration.safeTransfer(account, consToSend);
        emit Redeemed(address(owner()), address(collateral), account, collToSend);
    }

    // ============ REDEEM CONSIDERATION (American only) ============

    /// @notice Convert `amount` Collateral tokens straight into consideration at the strike rate.
    ///         Only meaningful in American modes (Europeans never hold consideration — no exercise).
    /// @dev    Useful for a short-side holder who wants their payout settled in quote currency
    ///         rather than a mix of collateral and consideration.
    /// @param amount Collateral tokens to burn.
    ///
    /// Example:
    /// ```solidity
    /// // WETH/USDC call, strike 3000. Caller holds 1e18 CLL-WETH-USDC-3000-* and wants USDC:
    /// coll.redeemConsideration(1e18);   // burns coll, returns 3000e6 USDC (6-dec)
    /// ```
    function redeemConsideration(uint256 amount) public notLocked nonReentrant {
        if (isEuro) revert EuropeanExerciseDisabled();
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

    // ============ SETTLE + CLAIM (settled modes only) ============

    /// @notice Latch the oracle settlement price and initialise the option-holder reserve.
    ///         Callable by anyone post-expiry. Idempotent — subsequent calls are no-ops.
    /// @param hint Oracle-specific settlement hint (e.g. `abi.encode(roundId)` for Chainlink;
    ///             empty bytes for Uniswap v3 TWAP oracles).
    function settle(bytes calldata hint) public notLocked {
        _settle(hint);
    }

    /// @dev Internal settle — see {settle}.
    function _settle(bytes memory hint) internal {
        if (address(oracle) == address(0)) revert NoOracle();
        if (reserveInitialized) return;
        if (block.timestamp < expirationDate) revert ContractNotExpired();

        uint256 S = oracle.settle(hint);
        settlementPrice = S;
        uint256 K = strike;
        isItmAtSettle = S > K;
        if (S > K) {
            uint256 O = IERC20(owner()).totalSupply();
            optionReserveRemaining = Math.mulDiv(O, S - K, S);
        }
        reserveInitialized = true;
        emit Settled(S);
    }

    /// @notice Post-expiry exercise path invoked by {Option.exerciseFor}. Pulls consideration from
    ///         `consumer`, sends collateral to `recipient`, and decrements the option-reserve by the
    ///         residual the burned option would have claimed — keeping short-side redemption math
    ///         consistent with the {claim} path.
    /// @dev    Caller is the paired {Option}; gating (expired, settled, ITM, option-burn) lives there.
    /// @param consumer  Address paying consideration (typically a keeper/periphery contract).
    /// @param recipient Recipient of the collateral payout.
    /// @param amount    Collateral units to deliver; consideration collected is `ceil(amount * strike)`.
    function _exerciseForPostExpiry(address consumer, address recipient, uint256 amount)
        external
        notLocked
        onlyOwner
        sufficientCollateral(amount)
    {
        if (!reserveInitialized) _settle("");
        // ITM gate is a single SLOAD of the bool latched at first settle.
        if (!isItmAtSettle) revert NotITM();

        uint256 consAmount = toNeededConsideration(amount);
        if (consAmount == 0) revert InvalidValue();
        if (consAmount > type(uint160).max) revert ArithmeticOverflow();

        // Same residual formula as `_claimForOption` so reserve accounting stays exact.
        uint256 residual = Math.mulDiv(amount, settlementPrice - strike, settlementPrice);
        uint256 reserve = optionReserveRemaining;
        if (residual > reserve) residual = reserve;
        optionReserveRemaining = reserve - residual;

        uint256 consBefore = consideration.balanceOf(address(this));
        // forge-lint: disable-next-line(unsafe-typecast)
        _factory.transferFrom(consumer, address(this), uint160(consAmount), address(consideration));
        if (consideration.balanceOf(address(this)) - consBefore < consAmount) revert FeeOnTransferNotSupported();
        collateral.safeTransfer(recipient, amount);
    }

    /// @notice Pay an option-holder's ITM residual. Only callable by the paired Option.
    /// @dev    Payout formula: `amount * (S - K) / S`, floor-rounded, capped at the remaining
    ///         reserve. Zero if OTM (S ≤ K).
    /// @param holder  Recipient of the collateral payout.
    /// @param amount  Option tokens being burned on the long side.
    /// @return payout Collateral units actually sent.
    function _claimForOption(address holder, uint256 amount) external onlyOwner returns (uint256 payout) {
        // If `holder` opted into in-kind collateral, decrement their locked amount so the
        // cash-pool sizing stays accurate. Safe to call for non-opted holders too (no-op).
        uint256 lockedAmt = _collateralLocked[holder];
        if (lockedAmt > 0) {
            uint256 reduce = amount > lockedAmt ? lockedAmt : amount;
            _collateralLocked[holder] = lockedAmt - reduce;
            if (!cashSwapCompleted) totalCollateralReservedOptions -= reduce;
        }

        _settle("");
        uint256 S = settlementPrice;
        uint256 K = strike;
        if (S > K) {
            payout = Math.mulDiv(amount, S - K, S);
            uint256 reserve = optionReserveRemaining;
            if (payout > reserve) payout = reserve;
            if (payout > 0) {
                optionReserveRemaining = reserve - payout;
                collateral.safeTransfer(holder, payout);
            }
        }
        return payout;
    }

    // ============ CASH SETTLEMENT (opt-in) ============

    /// @notice Opt the caller out of the default consideration settlement and into
    ///         in-kind collateral. Locks the caller's current Option balance so the
    ///         upcoming one-shot swap skips that slice. Idempotent. Must be called
    ///         before {convertResidualToConsideration} runs.
    function requestCollateral() external expired notLocked {
        if (cashSwapCompleted) revert CashSwapAlreadyCompleted();
        if (wantsCollateral[msg.sender]) return;
        uint256 bal = IERC20(owner()).balanceOf(msg.sender);
        _collateralLocked[msg.sender] = bal;
        totalCollateralReservedOptions += bal;
        wantsCollateral[msg.sender] = true;
    }

    /// @notice Flip the caller back to the default consideration settlement. Releases
    ///         whatever remained of their collateral lock. Must be called before
    ///         {convertResidualToConsideration} runs.
    function requestConsideration() external expired notLocked {
        if (cashSwapCompleted) revert CashSwapAlreadyCompleted();
        if (!wantsCollateral[msg.sender]) return;
        uint256 locked = _collateralLocked[msg.sender];
        totalCollateralReservedOptions -= locked;
        _collateralLocked[msg.sender] = 0;
        wantsCollateral[msg.sender] = false;
    }

    /// @notice How many option units `holder` currently has locked for in-kind claim.
    function collateralLockedOf(address holder) external view returns (uint256) {
        return _collateralLocked[holder];
    }

    /// @notice One-shot, permissionless: swap the cash-reserved slice of the ITM reserve into
    ///         consideration via a caller-supplied swapper. Callers MUST set `minOut` to a
    ///         value that captures the oracle-implied value minus an acceptable slippage,
    ///         otherwise an MEV actor can sandwich the call.
    /// @dev    Idempotent after first completion; subsequent calls revert. Only meaningful
    ///         when the option settled ITM — otherwise there is no reserve to swap.
    /// @param  swapper   Implementation of {ISettlementSwapper} that will execute the swap.
    /// @param  minOut    Minimum consideration acceptable from the swap.
    /// @param  routeHint Opaque venue-specific calldata forwarded to the swapper — typically
    ///                   an off-chain-computed routing payload (e.g. Universal Router
    ///                   `(commands, inputs)` or a 0x API quote). Empty bytes when the
    ///                   swapper uses a bound pool.
    function convertResidualToConsideration(ISettlementSwapper swapper, uint256 minOut, bytes calldata routeHint)
        external
        expired
        notLocked
        nonReentrant
    {
        if (cashSwapCompleted) revert CashSwapAlreadyCompleted();
        _settle("");
        if (!isItmAtSettle) {
            // No reserve was set aside → nothing to convert. Mark complete so callers can't retry.
            cashSwapCompleted = true;
            return;
        }

        // Cash pool size = current Option supply minus holders who opted into in-kind collateral.
        uint256 totalOptions = IERC20(owner()).totalSupply();
        uint256 reservedColl = totalCollateralReservedOptions;
        uint256 cashOptions = totalOptions > reservedColl ? totalOptions - reservedColl : 0;
        if (cashOptions == 0) {
            cashSwapCompleted = true;
            return;
        }

        uint256 S = settlementPrice;
        uint256 K = strike;
        // Portion of the in-kind reserve that must convert to consideration.
        uint256 wethToSwap = Math.mulDiv(cashOptions, S - K, S);
        uint256 reserve = optionReserveRemaining;
        if (wethToSwap > reserve) wethToSwap = reserve;
        optionReserveRemaining = reserve - wethToSwap;

        // Pull the collateral out of the reserve and hand it to the swapper.
        collateral.forceApprove(address(swapper), wethToSwap);
        uint256 consOut =
            swapper.swap(address(collateral), address(consideration), wethToSwap, minOut, address(this), routeHint);
        if (consOut < minOut) revert SwapSlippage();

        // consOut is distributed pro-rata over the reserved options: each cash-claimed option
        // unit is worth (consOut / cashOptions) consideration.
        cashConsiderationPerOptionWad = Math.mulDiv(consOut, 1e18, cashOptions);
        cashSwapCompleted = true;
        emit CashConverted(wethToSwap, consOut, cashOptions);
    }

    /// @notice Cash-settlement payout. Only callable by the paired Option. Decrements the
    ///         holder's cash reservation and transfers consideration proportional to the
    ///         already-latched `cashConsiderationPerOptionWad`.
    /// @dev    Reverts if the holder has not yet reserved `amount` for cash, or if the
    ///         swap has not completed.
    function _claimCashForOption(address holder, uint256 amount) external onlyOwner returns (uint256 payout) {
        if (!cashSwapCompleted) revert CashSwapNotCompleted();
        payout = Math.mulDiv(amount, cashConsiderationPerOptionWad, 1e18);
        if (payout > 0) consideration.safeTransfer(holder, payout);
    }

    /// @notice Emitted by {convertResidualToConsideration} on the one-shot cash swap.
    event CashConverted(uint256 collateralIn, uint256 considerationOut, uint256 optionsReserved);

    // ============ SWEEPS ============

    /// @notice Redeem `holder`'s full Collateral balance post-expiry.
    ///         No-op for zero-balance accounts. Useful for gas-sponsored cleanup.
    /// @param holder The short-side holder to sweep.
    function sweep(address holder) public expired notLocked nonReentrant {
        uint256 amount = balanceOf(holder);
        if (amount == 0) return;
        if (address(oracle) != address(0)) {
            _settle("");
            _redeemSettled(holder, amount);
        } else {
            _redeemProRata(holder, amount);
        }
    }

    /// @notice Batch form of {sweep} — walks the array and redeems each holder's full balance.
    /// @dev    Settlement is latched once up front (in settled mode) so the oracle only runs once.
    /// @param holders Array of short-side holders to sweep.
    function sweep(address[] calldata holders) public expired notLocked nonReentrant {
        bool settled_ = address(oracle) != address(0);
        if (settled_) _settle("");
        for (uint256 i = 0; i < holders.length; i++) {
            address holder = holders[i];
            uint256 bal = balanceOf(holder);
            if (bal == 0) continue;
            if (settled_) {
                _redeemSettled(holder, bal);
            } else {
                _redeemProRata(holder, bal);
            }
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

    /// @notice Human-readable token name, mirroring {Option} but with a `CLL[E]-` prefix.
    ///         Puts display the inverted strike back in human form (`1e36 / strike`).
    function name() public view override returns (string memory) {
        uint256 displayStrike = isPut ? (1e36 / strike) : strike;
        return string(
            abi.encodePacked(
                isEuro ? "CLLE-" : "CLL-",
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

    /// @notice Decimals match the underlying collateral so 1 Collateral unit ↔ 1 collateral unit.
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

    /// @notice Paired Option contract (also this Collateral's owner).
    function option() public view returns (address) {
        return owner();
    }

    /// @notice Factory that created this option.
    function factory() public view returns (address) {
        return address(_factory);
    }
}
