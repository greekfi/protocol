// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { Initializable } from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import { ReentrancyGuardTransient } from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";
import { IERC20, ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

import { Collateral } from "./Collateral.sol";
import { TokenData, Balances, OptionInfo } from "./interfaces/IOption.sol";
import { OptionUtils } from "./OptionUtils.sol";
import { IPriceOracle } from "./oracles/IPriceOracle.sol";

/// @dev Narrow view of {Factory} used by {Option} for auto-mint/auto-redeem lookups
///      and operator (ERC1155-style blanket allowance) checks on transfers.
interface IFactoryView {
    function approvedOperator(address owner, address operator) external view returns (bool);
    function autoMintRedeem(address account) external view returns (bool);
}

/**
 * @title  Option — long-side ERC20
 * @author Greek.fi
 * @notice One half of a Greek option pair. Holding this token grants the *right* (not obligation)
 *         to buy the collateral at the strike price — a standard call — or, for puts, the right
 *         to sell. Its paired {Collateral} contract holds the short side of the same option.
 *
 *         Three behaviour modes are fixed at creation (driven by {Factory}):
 *
 *         | Mode                   | `oracle` | `isEuro` | Pre-expiry     | Post-expiry         |
 *         | ---------------------- | -------- | -------- | -------------- | ------------------- |
 *         | American non-settled   | `0`      | `false`  | `exercise`     | — (token is dust)   |
 *         | American settled       | set      | `false`  | `exercise`     | `claim` ITM residual|
 *         | European               | set      | `true`   | no exercise    | `claim` ITM residual|
 *
 *         The mode is read from the paired {Collateral} (`isEuro`, `oracle`).
 *
 *         ### Auto-mint / auto-redeem
 *
 *         Addresses that have opted in via `factory.enableAutoMintRedeem(true)` get two
 *         transfer-time conveniences:
 *
 *         - **Auto-mint** — if the sender tries to transfer more `Option` than they hold,
 *           the contract pulls enough collateral from the sender and mints the deficit.
 *         - **Auto-redeem** — if the receiver already holds the matching {Collateral} ("short")
 *           token, incoming `Option` is immediately redeemed pair-wise, returning collateral.
 *
 *         Both behaviours are opt-in per-account and make it possible to treat `Option` and
 *         its underlying collateral as interchangeable for power users (e.g. vaults).
 *
 * @dev    Deployed once as a template; the factory produces per-option instances via
 *         EIP-1167 minimal proxy clones. `init()` is used instead of a constructor.
 *
 *         Example (opening and exercising a call):
 *         ```solidity
 *         // 1. Deploy an option via the factory
 *         address opt = factory.createOption(
 *             CreateParams({
 *                 collateral:      WETH,
 *                 consideration:   USDC,
 *                 expirationDate:  uint40(block.timestamp + 30 days),
 *                 strike:          uint96(3000e18),        // 3000 USDC / WETH, 18-dec fixed point
 *                 isPut:           false,
 *                 isEuro:          false,
 *                 oracleSource:    address(0),             // American non-settled
 *                 twapWindow:      0
 *             })
 *         );
 *
 *         // 2. Mint 1 WETH worth of options (collateral-side approval on the factory)
 *         factory.approve(WETH, 1e18);
 *         Option(opt).mint(1e18);
 *
 *         // 3. If spot moves above strike, exercise before expiry
 *         factory.approve(USDC, 3000e6);                    // USDC is 6-dec
 *         Option(opt).exercise(1e18);                       // pays USDC, receives WETH
 *         ```
 */
contract Option is ERC20, Ownable, ReentrancyGuardTransient, Initializable {
    /// @notice Paired short-side ERC20 that holds the collateral and handles settlement math.
    Collateral public coll;

    /// @notice Emitted when new options are minted against fresh collateral.
    /// @param longOption  The Option contract (always `address(this)`).
    /// @param holder      The account credited with the new tokens.
    /// @param amount      Collateral-denominated amount (same decimals as the collateral token).
    event Mint(address longOption, address holder, uint256 amount);

    /// @notice Emitted when an option is exercised (American modes only).
    /// @param longOption  The Option contract (always `address(this)`).
    /// @param holder      The account receiving collateral.
    /// @param amount      Collateral units received (consideration paid is `toNeededConsideration(amount)`).
    event Exercise(address longOption, address holder, uint256 amount);

    /// @notice Emitted once when the oracle-settled spot price is latched on first settle.
    /// @param price 18-decimal fixed-point settlement price (consideration per collateral).
    event Settled(uint256 price);

    /// @notice Emitted on each post-expiry ITM claim.
    /// @param holder           Option holder whose tokens were burned.
    /// @param optionBurned     Option token amount burned.
    /// @param collateralOut    Collateral units paid out (the `(S-K)/S` ITM residual).
    event Claimed(address indexed holder, uint256 optionBurned, uint256 collateralOut);

    /// @notice Emitted when the owner pauses the contract.
    event ContractLocked();
    /// @notice Emitted when the owner unpauses the contract.
    event ContractUnlocked();

    /// @notice Thrown when a call that requires a live option is made after expiration.
    error ContractExpired();
    /// @notice Thrown when a post-expiry-only call (e.g. `claim`) is made before expiration.
    error ContractNotExpired();
    /// @notice Thrown when an account does not hold enough `Option` tokens for the operation.
    error InsufficientBalance();
    /// @notice Thrown when `amount == 0` or a similar non-zero invariant fails.
    error InvalidValue();
    /// @notice Thrown when a zero address is supplied where a contract is required.
    error InvalidAddress();
    /// @notice Thrown when the option (or its paired collateral) has been locked by the owner.
    error LockedContract();
    /// @notice Thrown when `exercise` is called on a European option.
    error EuropeanExerciseDisabled();
    /// @notice Thrown when `claim` / `settle` is called on an option that has no oracle.
    error NoOracle();

    /// @dev Blocks mutations while the paired collateral is locked by the owner.
    modifier notLocked() {
        if (coll.locked()) revert LockedContract();
        _;
    }

    /// @dev Blocks calls that require the option to still be live.
    modifier notExpired() {
        if (block.timestamp >= expirationDate()) revert ContractExpired();
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
    ///         through {init} instead. Disables initializers on the template to prevent takeover.
    /// @param name_   Placeholder name (overridden by the computed `name()` view).
    /// @param symbol_ Placeholder symbol (overridden by the computed `symbol()` view).
    constructor(string memory name_, string memory symbol_) ERC20(name_, symbol_) Ownable(msg.sender) {
        _disableInitializers();
    }

    /// @notice Initialises a freshly-cloned Option. Called exactly once by the factory.
    /// @param coll_  Address of the paired {Collateral} contract — immutable for this option.
    /// @param owner_ Admin of this option (receives `Ownable` rights; typically the user who
    ///               called `factory.createOption`).
    function init(address coll_, address owner_) public initializer {
        if (coll_ == address(0) || owner_ == address(0)) revert InvalidAddress();
        coll = Collateral(coll_);
        _transferOwnership(owner_);
    }

    // ============ VIEWS ============

    /// @notice Address of the {Factory} that created this option. Read from the paired Collateral.
    function factory() public view returns (address) {
        return coll.factory();
    }

    /// @notice Underlying collateral token (e.g. WETH for a WETH/USDC call).
    function collateral() public view returns (address) {
        return address(coll.collateral());
    }

    /// @notice Consideration / quote token (e.g. USDC for a WETH/USDC call).
    function consideration() public view returns (address) {
        return address(coll.consideration());
    }

    /// @notice Unix timestamp at which the option expires. After this, `exercise` reverts
    ///         and post-expiry paths (`claim`, `coll.redeem`) become active.
    function expirationDate() public view returns (uint256) {
        return coll.expirationDate();
    }

    /// @notice Strike price in 18-decimal fixed point, encoded as "consideration per collateral".
    /// @dev For puts, this stores the *inverse* of the human-readable strike (see {name} for display).
    function strike() public view returns (uint256) {
        return coll.strike();
    }

    /// @notice `true` if this is a put option; `false` for calls.
    function isPut() public view returns (bool) {
        return coll.isPut();
    }

    /// @notice `true` if the option is European-style (no pre-expiry exercise, oracle required).
    function isEuro() public view returns (bool) {
        return coll.isEuro();
    }

    /// @notice Oracle contract used for post-expiry settlement. `address(0)` in American non-settled mode.
    function oracle() public view returns (address) {
        return address(coll.oracle());
    }

    /// @notice `true` once the oracle price has been latched (first `settle` post-expiry).
    function isSettled() public view returns (bool) {
        return coll.reserveInitialized();
    }

    /// @notice Oracle settlement price (18-decimal fixed point). `0` until {settle} runs.
    function settlementPrice() public view returns (uint256) {
        return coll.settlementPrice();
    }

    /// @notice Option token shares the collateral's decimals so 1 option token ↔ 1 collateral unit.
    function decimals() public view override returns (uint8) {
        return IERC20Metadata(collateral()).decimals();
    }

    /// @notice Human-readable token name in the form `OPT[E]-<coll>-<cons>-<strike>-<YYYY-MM-DD>`.
    /// @dev For puts the displayed strike is inverted back (`1e36 / strike`) to the human form.
    ///      The `OPTE-` prefix flags European options.
    function name() public view override returns (string memory) {
        uint256 displayStrike = isPut() && strike() > 0 ? (1e36 / strike()) : strike();
        return string(
            abi.encodePacked(
                isEuro() ? "OPTE-" : "OPT-",
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
    /// @dev    Requires `factory.allowance(collateral, msg.sender) >= amount` (factory acts as the
    ///         single collateral transfer point). Reverts if the option is expired or locked.
    /// @param amount Collateral-denominated amount to mint (≤ `type(uint160).max`).
    ///
    /// Example:
    /// ```solidity
    /// IERC20(WETH).approve(address(factory), 1e18);
    /// factory.approve(WETH, 1e18);
    /// option.mint(1e18);                   // caller receives 1e18 Option + 1e18 Collateral tokens
    /// ```
    function mint(uint256 amount) public notLocked {
        mint(msg.sender, amount);
    }

    /// @notice Mint `amount` option tokens to `account`. Collateral is pulled from `account`.
    /// @dev    The factory enforces `approvedOperator(account, msg.sender)` / `allowance` rules —
    ///         minting "for" a third party still requires their approval.
    /// @param account Recipient of both `Option` and `Collateral` tokens.
    /// @param amount  Collateral-denominated mint amount.
    function mint(address account, uint256 amount) public notLocked nonReentrant {
        mint_(account, amount);
    }

    /// @dev Internal mint path shared by `mint` and auto-mint-on-transfer.
    function mint_(address account, uint256 amount) internal notExpired validAmount(amount) {
        coll.mint(account, amount);
        _mint(account, amount);
        emit Mint(address(this), account, amount);
    }

    // ============ TRANSFER (auto-mint + auto-redeem) ============

    /// @dev Core transfer hook implementing auto-mint (sender) and auto-redeem (receiver).
    ///      Both are gated on each party's `autoMintRedeem` opt-in held on the factory.
    function _settledTransfer(address from, address to, uint256 amount) internal {
        uint256 balance = balanceOf(from);
        if (balance < amount) {
            if (!IFactoryView(factory()).autoMintRedeem(from)) revert InsufficientBalance();
            uint256 deficit = amount - balance;
            mint_(from, deficit);
        }

        _transfer(from, to, amount);

        if (IFactoryView(factory()).autoMintRedeem(to)) {
            uint256 collBal = coll.balanceOf(to);
            if (collBal > 0) {
                redeem_(to, Math.min(collBal, amount));
            }
        }
    }

    /// @inheritdoc ERC20
    /// @dev Overridden to run the auto-mint / auto-redeem hook. Reverts post-expiry —
    ///      the long token stops circulating once settlement begins.
    function transfer(address to, uint256 amount) public override notExpired notLocked nonReentrant returns (bool) {
        _settledTransfer(msg.sender, to, amount);
        return true;
    }

    /// @inheritdoc ERC20
    /// @dev Skips `_spendAllowance` when `msg.sender` is a factory-approved operator for `from`
    ///      (ERC-1155 style blanket approval across every option in the protocol).
    function transferFrom(address from, address to, uint256 amount)
        public
        override
        notExpired
        notLocked
        nonReentrant
        returns (bool)
    {
        if (msg.sender != from && !IFactoryView(factory()).approvedOperator(from, msg.sender)) {
            _spendAllowance(from, msg.sender, amount);
        }
        _settledTransfer(from, to, amount);
        return true;
    }

    // ============ EXERCISE (American only) ============

    /// @notice Exercise `amount` options as the caller: pay consideration, receive collateral.
    /// @dev    American-only. European options revert with `EuropeanExerciseDisabled`.
    ///         Requires the caller to hold at least `amount` option tokens AND have
    ///         `factory.allowance(consideration, caller) >= toNeededConsideration(amount)`.
    /// @param amount Collateral units to receive. Consideration paid = `ceil(amount * strike)`.
    ///
    /// Example:
    /// ```solidity
    /// // WETH/USDC call, strike 3000. Exercise 1e18 (1 WETH):
    /// factory.approve(USDC, 3000e6);
    /// option.exercise(1e18);
    /// ```
    function exercise(uint256 amount) public notLocked {
        exercise(msg.sender, amount);
    }

    /// @notice Exercise `amount` options on behalf of `account`; caller pays consideration,
    ///         `account` receives collateral, caller's option balance is burned.
    /// @param account Address receiving the collateral payout.
    /// @param amount  Collateral units to exercise.
    function exercise(address account, uint256 amount) public notExpired notLocked nonReentrant validAmount(amount) {
        if (isEuro()) revert EuropeanExerciseDisabled();
        _burn(msg.sender, amount);
        coll.exercise(account, amount, msg.sender);
        emit Exercise(address(this), msg.sender, amount);
    }

    // ============ PRE-EXPIRY PAIR REDEEM ============

    /// @notice Burn matched `Option` + `Collateral` pairs to recover the underlying collateral.
    /// @dev    Pre-expiry only. Caller must hold both sides in equal amount. Useful for closing
    ///         a position you hold both sides of (e.g. a market maker winding down inventory).
    /// @param amount Collateral-denominated amount to redeem from each side.
    ///
    /// Example:
    /// ```solidity
    /// // Holding 1e18 Option + 1e18 Collateral from a prior mint:
    /// option.redeem(1e18);             // burns both, returns 1e18 WETH
    /// ```
    function redeem(uint256 amount) public notLocked nonReentrant {
        redeem_(msg.sender, amount);
    }

    /// @dev Internal pair-redeem. Burns Option side here, delegates Collateral-side burn + payout
    ///      to the paired {Collateral} contract.
    function redeem_(address account, uint256 amount) internal notExpired sufficientBalance(account, amount) {
        _burn(account, amount);
        coll._redeemPair(account, amount);
    }

    // ============ POST-EXPIRY SETTLE + CLAIM (settled modes only) ============

    /// @notice Latch the oracle settlement price. Callable by anyone post-expiry. Idempotent.
    /// @dev    Required before `claim` can pay out. Forwarded to the paired collateral;
    ///         implementation-specific `hint` (e.g. a Chainlink `roundId`) is passed through.
    /// @param  hint Oracle-specific settlement hint; empty bytes for `UniV3Oracle`.
    function settle(bytes calldata hint) external notLocked {
        if (address(coll.oracle()) == address(0)) revert NoOracle();
        coll.settle(hint);
        emit Settled(coll.settlementPrice());
    }

    /// @notice Claim the caller's full Option balance. Convenience wrapper that burns
    ///         `balanceOf(msg.sender)` and routes the payout per the holder's
    ///         {Collateral.wantsCollateral} flag (default = consideration/cash).
    function claim() external notLocked nonReentrant {
        _claim(msg.sender, balanceOf(msg.sender));
    }

    /// @notice Claim the specified `amount` for the caller. Delegates to the workhorse.
    function claim(uint256 amount) external notLocked nonReentrant {
        _claim(msg.sender, amount);
    }

    /// @notice Permissionless claim on behalf of `holder` — burns `holder`'s full balance
    ///         and sends the payout to `holder`. Anyone can call; useful for gas-sponsored
    ///         sweeps. No-op when the holder's balance is zero.
    function claim(address holder) external notLocked nonReentrant {
        uint256 bal = balanceOf(holder);
        if (bal == 0) return;
        _claim(holder, bal);
    }

    /// @notice Permissionless claim on behalf of `holder` for a specified `amount`. The
    ///         core workhorse — all other `claim` overloads route through here.
    /// @dev    Payout always goes to `holder`; `msg.sender` only pays gas. Routes to the
    ///         in-kind reserve if `holder` opted into collateral AND has enough locked
    ///         for `amount`; otherwise routes to the cash pool (post-swap) or silently
    ///         falls back to in-kind (pre-swap).
    function claim(address holder, uint256 amount) external notLocked nonReentrant {
        _claim(holder, amount);
    }

    /// @dev Shared claim workhorse. Gates, routes, burns, pays.
    function _claim(address holder, uint256 amount) internal validAmount(amount) sufficientBalance(holder, amount) {
        if (address(coll.oracle()) == address(0)) revert NoOracle();
        if (block.timestamp < expirationDate()) revert ContractNotExpired();

        uint256 payout;
        // In-kind path: holder opted into collateral AND has `amount` locked. Else cash path
        // (if swap completed) or silent fallback to in-kind (pre-swap safety).
        bool inKind = coll.wantsCollateral(holder) && coll.collateralLockedOf(holder) >= amount;
        if (!inKind && coll.cashSwapCompleted()) {
            _burn(holder, amount);
            payout = coll._claimCashForOption(holder, amount);
        } else {
            coll.settle(""); // idempotent; safe to call even if already settled
            _burn(holder, amount);
            payout = coll._claimForOption(holder, amount);
        }
        emit Claimed(holder, amount, payout);
    }

    /// @notice Post-expiry permissionless exercise. Burns `amount` from `holder`, pulls
    ///         `toNeededConsideration(amount)` consideration from `msg.sender`, and sends `amount`
    ///         collateral to `recipient`. Economically: the caller buys the option at strike.
    /// @dev    Only valid in settled modes with an oracle, post-expiry, and only when ITM.
    ///         Decrements `optionReserveRemaining` by the burned option's residual so that
    ///         short-side redemption accounting stays consistent with {claim}.
    /// @param holder    Option holder whose tokens will be burned.
    /// @param amount    Collateral units to exercise.
    /// @param recipient Recipient of the collateral payout (typically a keeper).
    function exerciseFor(address holder, uint256 amount, address recipient)
        external
        notLocked
        nonReentrant
        validAmount(amount)
        sufficientBalance(holder, amount)
    {
        _burn(holder, amount);
        coll._exerciseForPostExpiry(msg.sender, recipient, amount);
        emit Exercise(address(this), holder, amount);
    }

    /// @notice Batch variant: same semantics as `exerciseFor(holder, amount, recipient)`
    ///         applied to a list of holders in one transaction. Saves the per-call external
    ///         CALL + selector dispatch vs. a keeper that loops `exerciseFor` from outside.
    /// @dev    Arrays must be equal length. Skips holders with zero balance rather than
    ///         reverting, so stale addresses in a keeper's holder list do not abort the sweep.
    /// @param  holders    Option holders whose tokens will be burned.
    /// @param  amounts    Per-holder collateral units to exercise.
    /// @param  recipient  Address receiving all collateral payouts.
    function exerciseFor(address[] calldata holders, uint256[] calldata amounts, address recipient)
        external
        notLocked
        nonReentrant
    {
        uint256 n = holders.length;
        if (n != amounts.length) revert InvalidValue();
        Collateral c = coll;
        for (uint256 i = 0; i < n; i++) {
            address h = holders[i];
            uint256 a = amounts[i];
            if (a == 0) continue;
            if (balanceOf(h) < a) continue;
            _burn(h, a);
            c._exerciseForPostExpiry(msg.sender, recipient, a);
            emit Exercise(address(this), h, a);
        }
    }

    // ============ QUERY ============

    /// @notice All four balances that matter for this option in one call.
    /// @param account Address to query.
    /// @return A {Balances} struct: collateral token, consideration token, long option, short coll.
    function balancesOf(address account) public view returns (Balances memory) {
        return Balances({
            collateral: IERC20(collateral()).balanceOf(account),
            consideration: IERC20(consideration()).balanceOf(account),
            option: balanceOf(account),
            coll: coll.balanceOf(account)
        });
    }

    /// @notice Full option descriptor — addresses, token metadata, strike, expiry, flags.
    ///         Convenient one-shot read for frontends.
    function details() public view returns (OptionInfo memory) {
        address colTok = collateral();
        address consTok = consideration();
        IERC20Metadata cm = IERC20Metadata(colTok);
        IERC20Metadata cnm = IERC20Metadata(consTok);
        return OptionInfo({
            option: address(this),
            coll: address(coll),
            collateral: TokenData({ address_: colTok, name: cm.name(), symbol: cm.symbol(), decimals: cm.decimals() }),
            consideration: TokenData({
                address_: consTok, name: cnm.name(), symbol: cnm.symbol(), decimals: cnm.decimals()
            }),
            expiration: expirationDate(),
            strike: strike(),
            isPut: isPut(),
            isEuro: isEuro(),
            oracle: oracle()
        });
    }

    // ============ ADMIN ============

    /// @notice Emergency pause — blocks all state-changing paths on this option and its pair.
    /// @dev    Only callable by the option's owner (the account that called `createOption`).
    function lock() public onlyOwner {
        coll.lock();
        emit ContractLocked();
    }

    /// @notice Resume a previously locked option.
    function unlock() public onlyOwner {
        coll.unlock();
        emit ContractUnlocked();
    }

    /// @notice Ownership renouncement is permanently disabled — an unowned option has no recovery path.
    function renounceOwnership() public pure override {
        revert InvalidAddress();
    }
}
