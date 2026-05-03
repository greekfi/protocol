// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { ReentrancyGuardTransient } from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";
import { IERC20, ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

import { Receipt } from "./Receipt.sol";
import { TokenData, Balances, OptionInfo } from "./interfaces/IOption.sol";
import { OptionUtils } from "./OptionUtils.sol";

/// @dev Narrow view of {Factory} used by {Option} for auto-mint/auto-burn lookups
///      and operator (ERC1155-style blanket allowance) checks on transfers.
interface IFactory {
    function approvedOperator(address owner, address operator) external view returns (bool);
    function autoMintBurn(address account) external view returns (bool);
    function exerciseAllowed(address holder, address exercisor) external view returns (bool);
}

/**
 * @title  Option — long-side ERC20
 * @author Greek.fi
 * @notice One half of a Greek option pair. Holding this token grants the *right* (not obligation)
 *         to buy the collateral at the strike price — a standard call — or, for puts, the right
 *         to sell. Its paired {Receipt} contract holds the short side of the same option.
 *
 *         Settlement is purely time-gated, no oracle is consulted at any point. Two flavours
 *         coexist, chosen at creation by `isEuro`:
 *
 *         | Mode      | `isEuro` | Pre-expiry exercise | In-window exercise | Post-window      |
 *         | --------- | -------- | ------------------- | ------------------ | ---------------- |
 *         | American  | `false`  | allowed             | allowed            | short pro-rata   |
 *         | European  | `true`   | reverts             | allowed            | short pro-rata   |
 *
 *         The exercise window is `[expirationDate, exerciseDeadline)` where
 *         `exerciseDeadline = expirationDate + windowSeconds` (default 8 hours, settable per
 *         option). The holder decides off-chain whether ITM is profitable and pays strike to
 *         exercise; the protocol just enforces timing and the 1:1 collateral invariant.
 *         Pair `burn` (matched long+short burn) stays valid the entire option lifetime.
 *
 *         ### Auto-mint / auto-burn
 *
 *         Addresses that have opted in via `factory.enableAutoMintBurn(true)` get two
 *         transfer-time conveniences:
 *
 *         - **Auto-mint** — if the sender tries to transfer more `Option` than they hold,
 *           the contract pulls enough collateral from the sender and mints the deficit.
 *         - **Auto-burn** — if the receiver already holds the matching {Receipt} ("short")
 *           token, incoming `Option` is immediately burned pair-wise, returning collateral.
 *
 *         Both behaviours are opt-in per-account and make it possible to treat `Option` and
 *         its underlying collateral as interchangeable for power users (e.g. vaults).
 *
 * @dev    Deployed once as a template; the factory produces per-option instances via
 *         EIP-1167 minimal proxy clones. `init()` is used instead of a constructor.
 */
contract Option is ERC20, ReentrancyGuardTransient {
    /// @notice Paired short-side ERC20 (collateral receipt) that holds the collateral and handles
    ///         settlement math. Doubles as the {init} guard — non-zero means initialised.
    Receipt public receipt;

    /// @notice Factory that created this option. Set in the template constructor (= the factory
    ///         that deployed it) and inherited by every clone via the template's runtime bytecode.
    IFactory public immutable FACTORY;

    /// @notice Emitted when new options are minted against fresh collateral.
    /// @param longOption  The Option contract (always `address(this)`).
    /// @param holder      The account credited with the new tokens.
    /// @param amount      Collateral-denominated amount (same decimals as the collateral token).
    event Mint(address longOption, address holder, uint256 amount);

    /// @notice Emitted when an option is exercised.
    /// @param longOption  The Option contract (always `address(this)`).
    /// @param caller      The account that initiated the exercise.
    /// @param holder      The account whose options were burned.
    /// @param amount      Collateral units delivered (consideration paid is `toNeededConsideration(amount)`).
    event Exercise(address longOption, address caller, address holder, uint256 amount);

    /// @notice Thrown when a call that requires a live option is made after expiration.
    error ContractExpired();
    /// @notice Thrown when an account does not hold enough `Option` tokens for the operation.
    error InsufficientBalance();
    /// @notice Thrown when `amount == 0` or array lengths mismatch.
    error InvalidValue();
    /// @notice Thrown when a zero address is supplied where a contract is required.
    error InvalidAddress();
    /// @notice Thrown when exercise is attempted after `exerciseDeadline`.
    error ExerciseWindowClosed();
    /// @notice Thrown when pre-expiry exercise is attempted on a European option.
    error EuropeanExerciseDisabled();
    /// @notice Thrown when the caller has not been authorised to exercise on the holder's behalf.
    error ExerciseNotAllowed();
    /// @notice Thrown when {init} is called on a clone that has already been initialised, or on
    ///         the template (whose `receipt` is set to a sentinel by the constructor).
    error AlreadyInitialized();
    /// @notice Thrown when {init} is called by anyone other than the factory.
    error UnauthorizedCaller();

    /// @dev Blocks `mint_` once the option has expired — no new options past expiration.
    modifier notExpired() {
        if (block.timestamp >= expirationDate()) revert ContractExpired();
        _;
    }

    /// @dev Blocks transfer / pair-burn paths once the exercise window has closed; the long token
    ///      remains circulating throughout the window so holders can still sell to keepers.
    modifier notPastDeadline() {
        if (block.timestamp >= receipt.exerciseDeadline()) revert ExerciseWindowClosed();
        _;
    }

    /// @dev Gates exercise paths. European reverts pre-expiry with the specific reason; both
    ///      flavours revert with `ExerciseWindowClosed` past `exerciseDeadline`.
    modifier canExercise() {
        if (isEuro() && block.timestamp < expirationDate()) revert EuropeanExerciseDisabled();
        if (block.timestamp > receipt.exerciseDeadline()) revert ExerciseWindowClosed();
        _;
    }

    /// @dev Rejects zero-amount mutations to keep accounting clean and events meaningful.
    modifier validAmount(uint256 amount) {
        if (amount == 0) revert InvalidValue();
        _;
    }

    /// @dev Ensures `account` holds at least `amount` Option tokens.
    modifier sufficientBalance(address account, uint256 amount) {
        if (balanceOf(account) < amount) revert InsufficientBalance();
        _;
    }

    /// @notice Template constructor. Never called for user-facing instances; each clone goes
    ///         through {init} instead. Sets `receipt` to a non-zero sentinel so the template
    ///         itself fails the {init} guard.
    constructor(string memory name_, string memory symbol_) ERC20(name_, symbol_) {
        FACTORY = IFactory(msg.sender);
        receipt = Receipt(address(0xdead));
    }

    /// @notice Initialises a freshly-cloned Option. Called exactly once by the factory.
    /// @param receipt_ Address of the paired {Receipt} contract — immutable for this option.
    function init(address receipt_) public {
        if (address(receipt) != address(0)) revert AlreadyInitialized();
        if (msg.sender != address(FACTORY)) revert UnauthorizedCaller();
        if (receipt_ == address(0)) revert InvalidAddress();
        receipt = Receipt(receipt_);
    }

    // ============ VIEWS ============

    /// @notice Address of the {Factory} that created this option. Read from the paired Receipt.
    function factory() public view returns (address) {
        return address(FACTORY);
    }

    /// @notice Underlying collateral token (e.g. WETH for a WETH/USDC call).
    function collateral() public view returns (address) {
        return address(receipt.collateral());
    }

    /// @notice Consideration / quote token (e.g. USDC for a WETH/USDC call).
    function consideration() public view returns (address) {
        return address(receipt.consideration());
    }

    /// @notice Unix timestamp at which the option expires.
    function expirationDate() public view returns (uint256) {
        return receipt.expirationDate();
    }

    /// @notice Unix timestamp at which the post-expiry exercise window closes.
    function exerciseDeadline() public view returns (uint40) {
        return receipt.exerciseDeadline();
    }

    /// @notice Strike price in 18-decimal fixed point, encoded as "consideration per collateral".
    /// @dev For puts, this stores the *inverse* of the human-readable strike (see {name} for display).
    function strike() public view returns (uint256) {
        return receipt.strike();
    }

    /// @notice `true` if this is a put option; `false` for calls.
    function isPut() public view returns (bool) {
        return receipt.isPut();
    }

    /// @notice `true` for European-style options (exercise barred pre-expiry; only the post-expiry
    ///         window is exercisable). `false` for American (any time before `exerciseDeadline`).
    function isEuro() public view returns (bool) {
        return receipt.isEuro();
    }

    /// @notice Option token shares the collateral's decimals so 1 option token ↔ 1 collateral unit.
    function decimals() public view override returns (uint8) {
        return IERC20Metadata(collateral()).decimals();
    }

    /// @notice Human-readable token name in the form `OPT[E/A]-<coll>-<cons>-<strike>-<YYYY-MM-DD>`.
    ///         The `OPTE-` prefix flags European options, `OPTA-` flags American options.
    /// @dev For puts the displayed strike is inverted back (`1e36 / strike`) to the human form.
    function name() public view override returns (string memory) {
        uint256 displayStrike = isPut() && strike() > 0 ? (1e36 / strike()) : strike();
        return string(
            abi.encodePacked(
                isEuro() ? "OPTE-" : "OPTA-",
                IERC20Metadata(collateral()).symbol(),
                "-",
                IERC20Metadata(consideration()).symbol(),
                "-",
                OptionUtils.strike2str(displayStrike),
                "-",
                OptionUtils.epoch2str(expirationDate())
            )
        );
    }

    /// @notice Same as {name}. Matching name/symbol keeps wallets and explorers in sync.
    function symbol() public view override returns (string memory) {
        return name();
    }

    // ============ MINT ============

    /// @notice Mint `amount` option tokens to the caller, collateralised 1:1 with the underlying.
    function mint(uint256 amount) public {
        mint(msg.sender, amount);
    }

    /// @notice Mint `amount` option tokens to `account`. Collateral is pulled from `account`.
    /// @param account Recipient of both `Option` and `Receipt` tokens.
    /// @param amount  Collateral-denominated mint amount.
    function mint(address account, uint256 amount) public nonReentrant {
        mint_(account, amount);
    }

    /// @dev Internal mint path shared by `mint` and auto-mint-on-transfer.
    function mint_(address account, uint256 amount) internal notExpired validAmount(amount) {
        receipt.mint(account, amount);
        _mint(account, amount);
        emit Mint(address(this), account, amount);
    }

    // ============ TRANSFER (auto-mint + auto-burn) ============

    /// @dev Auto-mint (sender) + auto-burn (receiver) hook around the underlying ERC20 transfer.
    ///      Both legs are gated on each party's `autoMintBurn` opt-in held on the factory.
    ///      Not an override of OZ's `_transfer` (which is non-virtual) — callable from the public
    ///      transfer paths only, so mint/burn don't trigger it.
    function _settledTransfer(address from, address to, uint256 value) internal {
        uint256 balance = balanceOf(from);
        if (balance < value) {
            if (!FACTORY.autoMintBurn(from)) revert InsufficientBalance();
            mint_(from, value - balance);
        }

        _transfer(from, to, value);

        if (FACTORY.autoMintBurn(to)) {
            uint256 receiptBal = receipt.balanceOf(to);
            if (receiptBal > 0) {
                burn_(to, Math.min(receiptBal, value));
            }
        }
    }

    /// @inheritdoc ERC20
    /// @dev Overridden to run the auto-mint / auto-burn hook. Reverts post-expiry —
    ///      the long token stops circulating once expiration passes.
    function transfer(address to, uint256 amount) public override notPastDeadline nonReentrant returns (bool) {
        _settledTransfer(msg.sender, to, amount);
        return true;
    }

    /// @inheritdoc ERC20
    /// @dev Skips `_spendAllowance` when `msg.sender` is a factory-approved operator for `from`
    ///      (ERC-1155 style blanket approval across every option in the protocol).
    function transferFrom(address from, address to, uint256 amount)
        public
        override
        notPastDeadline
        nonReentrant
        returns (bool)
    {
        if (msg.sender != from && !FACTORY.approvedOperator(from, msg.sender)) {
            _spendAllowance(from, msg.sender, amount);
        }
        _settledTransfer(from, to, amount);
        return true;
    }

    // ============ EXERCISE ============

    /// @notice Exercise `amount` options as the caller: pay consideration, receive collateral.
    /// @dev    Allowed pre-expiry and within the post-expiry exercise window.
    /// @param amount Collateral units to receive. Consideration paid = `ceil(amount * strike)`.
    function exercise(uint256 amount) public {
        exercise(msg.sender, amount);
    }

    /// @notice Exercise `amount` options held by `holder`. Caller pays consideration and receives
    ///         the collateral; if `holder` is owed any economic surplus the caller is responsible
    ///         for delivering it off-band.
    /// @dev    Caller must be `holder` themselves or have been authorised by `holder` via
    ///         `factory.allowExercise` or the blanket `factory.approveOperator`. Allowed any time
    ///         exercise itself is allowed (pre-expiry for American, plus the post-expiry window
    ///         for both flavours).
    /// @param holder Option holder whose tokens will be burned.
    /// @param amount Collateral units to exercise.
    function exercise(address holder, uint256 amount)
        public
        canExercise
        nonReentrant
        validAmount(amount)
        sufficientBalance(holder, amount)
    {
        if (msg.sender != holder && !FACTORY.exerciseAllowed(holder, msg.sender)) {
            revert ExerciseNotAllowed();
        }
        _burn(holder, amount);
        receipt.exercise(msg.sender, amount, msg.sender);
        emit Exercise(address(this), msg.sender, holder, amount);
    }

    /// @notice Batch variant of {exercise(address,uint256)}. Caller receives all collateral and
    ///         pays consideration on every entry. Entries that fail the per-holder allowance
    ///         check, have zero amount, or have insufficient balance are skipped rather than
    ///         reverting, so a stale or unauthorised address in a keeper's holder list does not
    ///         abort the sweep.
    /// @param holders Option holders whose tokens will be burned.
    /// @param amounts Per-holder collateral units to exercise (must be same length as `holders`).
    function exercise(address[] calldata holders, uint256[] calldata amounts) external canExercise nonReentrant {
        uint256 n = holders.length;
        if (n != amounts.length) revert InvalidValue();
        Receipt r = receipt;
        IFactory f = FACTORY;
        for (uint256 i = 0; i < n; i++) {
            address h = holders[i];
            uint256 a = amounts[i];
            if (a == 0) a = balanceOf(h);
            if (balanceOf(h) < a) continue;
            if (msg.sender != h && !f.exerciseAllowed(h, msg.sender)) continue;
            _burn(h, a);
            r.exercise(msg.sender, a, msg.sender);
            emit Exercise(address(this), msg.sender, h, a);
        }
    }

    // ============ PAIR burn (always valid) ============

    /// @notice Burn matched `Option` + `Receipt` pairs to recover the underlying collateral.
    /// @dev    Available the entire option lifetime (pair redemption is always valid; it doesn't
    ///         depend on the window because both long and short are burned in equal amount).
    ///         Caller must hold both sides in equal amount.
    /// @param amount Collateral-denominated amount to burn from each side.
    function burn(uint256 amount) public nonReentrant {
        burn_(msg.sender, amount);
    }

    /// @dev Internal pair-burn. Burns Option side here, delegates Receipt-side burn + payout
    ///      to the paired {Receipt} contract.
    function burn_(address account, uint256 amount) internal sufficientBalance(account, amount) {
        _burn(account, amount);
        receipt.burn(account, amount);
    }

    // ============ QUERY ============

    /// @notice All four balances that matter for this option in one call.
    /// @param account Address to query.
    /// @return A {Balances} struct: collateral token, consideration token, long option, short receipt.
    function balancesOf(address account) public view returns (Balances memory) {
        return Balances({
            collateral: IERC20(collateral()).balanceOf(account),
            consideration: IERC20(consideration()).balanceOf(account),
            option: balanceOf(account),
            receipt: receipt.balanceOf(account)
        });
    }

    /// @notice Full option descriptor — addresses, token metadata, strike, expiry, deadline.
    ///         Convenient one-shot read for frontends.
    function details() public view returns (OptionInfo memory) {
        address colTok = collateral();
        address consTok = consideration();
        IERC20Metadata cm = IERC20Metadata(colTok);
        IERC20Metadata cnm = IERC20Metadata(consTok);
        return OptionInfo({
            option: address(this),
            receipt: address(receipt),
            collateral: TokenData({ address_: colTok, name: cm.name(), symbol: cm.symbol(), decimals: cm.decimals() }),
            consideration: TokenData({
                address_: consTok, name: cnm.name(), symbol: cnm.symbol(), decimals: cnm.decimals()
            }),
            expiration: expirationDate(),
            strike: strike(),
            isPut: isPut(),
            isEuro: isEuro(),
            exerciseDeadline: exerciseDeadline()
        });
    }
}
