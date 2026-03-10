// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { Redemption } from "./Redemption.sol";
import { TokenData, Balances, OptionInfo } from "./interfaces/IOption.sol";
import { OptionUtils } from "./OptionUtils.sol";

/// @notice Interface for OptionFactory's operator approval and auto-mint/redeem functions
interface IOptionFactory {
    function isApprovedForAll(address owner, address operator) external view returns (bool);
    function autoMintRedeem(address account) external view returns (bool);
}

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { Initializable } from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import { ReentrancyGuardTransient } from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";
import { IERC20, ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

using SafeERC20 for IERC20;

/**
 * @title Option
 * @notice Long position ERC20 in an option contract — gives holders the right to exercise
 * @dev Deployed as EIP-1167 minimal proxy clones via OptionFactory. Paired 1:1 with a
 *      Redemption contract (short position) which holds all collateral.
 *
 *      Key invariant: available_collateral == total_option_supply (always).
 *
 *      Opt-in auto-settling transfers (via factory.autoMintRedeem):
 *        - Auto-mint: transfer() mints the deficit from collateral if sender balance < amount
 *        - Auto-redeem: receiving Options while holding Redemptions burns matched pairs
 *
 *      Rounding policy: round DOWN on all payouts, round UP on all collections.
 *      Dust stays in the protocol; no user is ever shorted.
 */
contract Option is ERC20, Ownable, ReentrancyGuardTransient, Initializable {
    Redemption public redemption;
    uint64 public fee;
    uint64 public constant MAXFEE = 1e16; // Max fee is 1% (1e16 in 1e18 basis)

    event Mint(address longOption, address holder, uint256 amount);
    event Exercise(address longOption, address holder, uint256 amount);
    event FeeUpdated(uint64 oldFee, uint64 newFee);

    error ContractExpired();
    error InsufficientBalance();
    error InvalidValue();
    error InvalidAddress();
    error LockedContract();

    event ContractLocked();
    event ContractUnlocked();

    // ============ MODIFIERS ============

    /// @notice Ensures contract is not locked (emergency pause)
    modifier notLocked() {
        if (redemption.locked()) revert LockedContract();
        _;
    }

    /// @notice Ensures option has not expired
    modifier notExpired() {
        if (block.timestamp >= expirationDate()) revert ContractExpired();

        _;
    }

    /// @notice Reverts if amount is zero
    modifier validAmount(uint256 amount) {
        if (amount == 0) revert InvalidValue();
        _;
    }

    /// @notice Reverts if address is zero
    modifier validAddress(address account) {
        if (account == address(0)) revert InvalidAddress();
        _;
    }

    /// @notice Reverts if account's Option balance < amount
    modifier sufficientBalance(address contractHolder, uint256 amount) {
        if (balanceOf(contractHolder) < amount) revert InsufficientBalance();
        _;
    }

    // ============ CONSTRUCTOR & INITIALIZATION ============

    /**
     * @notice Template constructor — only used for the implementation contract
     * @dev Clones never execute the constructor; state is set via init().
     *      Calls _disableInitializers() to prevent init() on the template itself.
     */
    constructor(string memory name_, string memory symbol_, address redemption__)
        ERC20(name_, symbol_)
        Ownable(msg.sender)
    {
        redemption = Redemption(redemption__);
        _disableInitializers();
    }

    /**
     * @notice Initializes a cloned Option contract
     * @dev Called exactly once by OptionFactory.createOption() immediately after cloning.
     * @param redemption_ Paired Redemption contract address
     * @param owner Option creator who receives ownership
     * @param fee_ Protocol fee in 1e18 basis (max 1% = 1e16)
     */
    function init(address redemption_, address owner, uint64 fee_) public initializer {
        if (redemption_ == address(0) || owner == address(0)) revert InvalidAddress();

        if (fee_ > MAXFEE) revert InvalidValue();
        _transferOwnership(owner);
        redemption = Redemption(redemption_);
        fee = fee_;
    }

    // ============ VIEW FUNCTIONS ============

    /// @notice Factory that created this Option (delegated from Redemption)
    function factory() public view returns (address) {
        return redemption.factory();
    }

    /**
     * @notice Dynamic token name: OPT-{COLL}-{CONS}-{STRIKE}-{YYYY-MM-DD}
     * @dev For puts, strike is displayed as 1/strike (human-readable price)
     */
    function name() public view override returns (string memory) {
        // For put options, display inverted price (1/strike)
        uint256 displayStrike = isPut() && strike() > 0 ? (1e36 / strike()) : strike();

        return string(
            abi.encodePacked(
                "OPT-",
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

    /// @notice Token symbol (same as name)
    function symbol() public view override returns (string memory) {
        return name();
    }

    /// @notice Collateral token address (delegated from Redemption)
    function collateral() public view returns (address) {
        return address(redemption.collateral());
    }

    /// @notice Consideration token address (delegated from Redemption)
    function consideration() public view returns (address) {
        return address(redemption.consideration());
    }

    /// @notice Expiration unix timestamp (delegated from Redemption)
    function expirationDate() public view returns (uint256) {
        return redemption.expirationDate();
    }

    /// @notice Strike price in 18-decimal encoding (delegated from Redemption)
    function strike() public view returns (uint256) {
        return redemption.strike();
    }

    /// @notice True if put option, false if call (delegated from Redemption)
    function isPut() public view returns (bool) {
        return redemption.isPut();
    }

    // ============ MINTING FUNCTIONS ============

    /// @notice Mints Option + Redemption tokens for msg.sender by depositing collateral
    function mint(uint256 amount) public notLocked {
        mint(msg.sender, amount);
    }

    /// @notice Mints Option + Redemption tokens for `account`, pulling collateral from msg.sender
    function mint(address account, uint256 amount) public notLocked nonReentrant {
        mint_(account, amount);
    }

    /**
     * @notice Internal mint: deposits collateral via Redemption, then mints Option tokens minus fee
     * @dev Fee is deducted from the minted amount (not the collateral deposit).
     *      Both Option and Redemption apply the same fee formula, keeping supplies equal.
     */
    function mint_(address account, uint256 amount) internal notExpired validAmount(amount) {
        redemption.mint(account, amount);
        // Inline fee calculation (safe: max fee is 1%, can't overflow)
        unchecked {
            uint256 amountMinusFees = amount - ((amount * fee) / 1e18);
            _mint(account, amountMinusFees);
            emit Mint(address(this), account, amountMinusFees);
        }
    }

    // ============ TRANSFER FUNCTIONS (WITH AUTO-SETTLING) ============

    /**
     * @notice ERC20 transferFrom with universal operator approval and opt-in auto-redeem
     * @dev Supports factory.isApprovedForAll() — approved operators can transfer any
     *      Option token created by this factory without individual ERC20 approvals.
     *      If recipient opted into autoMintRedeem and holds Redemption tokens,
     *      matched Option+Redemption pairs are automatically redeemed post-transfer.
     */
    function transferFrom(address from, address to, uint256 amount)
        public
        override
        notExpired
        notLocked
        nonReentrant
        returns (bool success)
    {
        // Check if caller has universal operator approval via factory
        // If so, use _transfer directly instead of super.transferFrom (which checks allowance)
        if (msg.sender != from && IOptionFactory(factory()).isApprovedForAll(from, msg.sender)) {
            _transfer(from, to, amount);
            success = true;
        } else {
            success = super.transferFrom(from, to, amount);
        }

        // Auto-redeem: if recipient opted in and holds Redemption tokens, burn matched pairs
        if (IOptionFactory(factory()).autoMintRedeem(to)) {
            uint256 balance = redemption.balanceOf(to);
            if (balance > 0) {
                redeem_(to, Math.min(balance, amount));
            }
        }
    }

    /**
     * @notice ERC20 transfer with opt-in auto-mint and auto-redeem
     * @dev Auto-mint (opt-in): if sender balance < amount, mints the deficit from collateral.
     *      The mint amount is fee-adjusted (ceil) so the sender ends up with >= amount tokens.
     *      Auto-redeem (opt-in): if recipient holds Redemption tokens, matched pairs are burned.
     */
    function transfer(address to, uint256 amount)
        public
        override
        notExpired
        notLocked
        nonReentrant
        validAddress(to)
        returns (bool success)
    {
        uint256 balance = balanceOf(msg.sender);
        if (balance < amount) {
            // Auto-mint: only if sender opted in, otherwise revert (standard ERC20)
            if (!IOptionFactory(factory()).autoMintRedeem(msg.sender)) revert InsufficientBalance();
            // Mint fee-adjusted amount so sender has enough tokens after fee deduction
            uint256 deficit = amount - balance;
            uint256 mintAmount = fee > 0 ? Math.mulDiv(deficit, 1e18, 1e18 - fee, Math.Rounding.Ceil) : deficit;
            mint_(msg.sender, mintAmount);
        }

        success = super.transfer(to, amount);
        require(success, "Transfer failed");

        // Auto-redeem: if recipient opted in and holds Redemption tokens, burn matched pairs
        if (IOptionFactory(factory()).autoMintRedeem(to)) {
            balance = redemption.balanceOf(to);
            if (balance > 0) {
                redeem_(to, Math.min(balance, amount));
            }
        }
    }

    // ============ EXERCISE FUNCTIONS ============

    /// @notice Exercises options for msg.sender — burns Options, pays consideration, receives collateral
    function exercise(uint256 amount) public notLocked {
        exercise(msg.sender, amount);
    }

    /**
     * @notice Exercises options — burns caller's Options, sends collateral to `account`
     * @dev Consideration is collected from msg.sender using toNeededConsideration (rounds UP).
     * @param account Recipient of the collateral
     * @param amount Number of Option tokens to exercise
     */
    function exercise(address account, uint256 amount) public notExpired notLocked nonReentrant validAmount(amount) {
        _burn(msg.sender, amount);
        redemption.exercise(account, amount, msg.sender);
        emit Exercise(address(this), msg.sender, amount);
    }

    // ============ REDEEM FUNCTIONS ============

    /**
     * @notice Pre-expiry pair redeem: burns matched Option + Redemption tokens, returns collateral
     * @param amount Number of pairs to redeem (must hold both tokens)
     */
    function redeem(uint256 amount) public notLocked nonReentrant {
        redeem_(msg.sender, amount);
    }

    /**
     * @notice Internal pair redeem — burns Option tokens, delegates to Redemption._redeemPair
     * @dev Pre-expiry only. The Redemption side burns Redemption tokens and returns collateral.
     *      Waterfall fallback to consideration exists as defense-in-depth but should never
     *      trigger because available_collateral == total_option_supply (invariant).
     */
    function redeem_(address account, uint256 amount) internal notExpired sufficientBalance(account, amount) {
        _burn(account, amount);
        redemption._redeemPair(account, amount);
    }

    // ============ QUERY FUNCTIONS ============

    /// @notice Decimals match the collateral token
    function decimals() public view override returns (uint8) {
        IERC20Metadata collMeta = IERC20Metadata(collateral());
        return collMeta.decimals();
    }

    /// @notice Returns all four token balances (collateral, consideration, option, redemption) for an account
    function balancesOf(address account) public view returns (Balances memory) {
        return Balances({
            collateral: IERC20(collateral()).balanceOf(account),
            consideration: IERC20(consideration()).balanceOf(account),
            option: balanceOf(account),
            redemption: redemption.balanceOf(account)
        });
    }

    /// @notice Returns complete option contract info (tokens, strike, expiry, type)
    function details() public view returns (OptionInfo memory) {
        // Cache addresses to avoid multiple delegatecalls
        address coll = collateral();
        address cons = consideration();

        // Cache metadata objects
        IERC20Metadata consMeta = IERC20Metadata(cons);
        IERC20Metadata collMeta = IERC20Metadata(coll);

        // Cache frequently accessed values
        uint256 exp = expirationDate();
        uint256 stk = strike();
        bool put = isPut();

        return OptionInfo({
            option: address(this),
            redemption: address(redemption),
            collateral: TokenData({
                address_: coll, name: collMeta.name(), symbol: collMeta.symbol(), decimals: collMeta.decimals()
            }),
            consideration: TokenData({
                address_: cons, name: consMeta.name(), symbol: consMeta.symbol(), decimals: consMeta.decimals()
            }),
            expiration: exp,
            strike: stk,
            isPut: put
        });
    }

    // ============ ADMIN FUNCTIONS ============

    /// @notice Emergency pause — prevents all mints, exercises, transfers, and redeems
    function lock() public onlyOwner {
        redemption.lock();
        emit ContractLocked();
    }

    /// @notice Unpause the contract
    function unlock() public onlyOwner {
        redemption.unlock();
        emit ContractUnlocked();
    }

    /**
     * @notice Updates the protocol fee for this option pair
     * @dev Propagates to the paired Redemption contract. Max 1% (1e16 in 1e18 basis).
     * @param fee_ New fee in 1e18 basis
     */
    function adjustFee(uint64 fee_) public onlyOwner {
        if (fee_ > MAXFEE) revert InvalidValue(); // Max fee is 1% (1e16 in 1e18 basis)
        uint64 oldFee = fee;
        fee = fee_;
        redemption.adjustFee(fee_);
        emit FeeUpdated(oldFee, fee_);
    }

    /**
     * @notice Moves accumulated fees from Redemption → Factory
     * @dev Permissionless — anyone can call. Funds always go to the factory (then to owner).
     *      Does not transfer to caller; just triggers the Redemption → Factory hop.
     */
    function claimFees() public nonReentrant {
        redemption.claimFees();
    }

    /// @notice Disabled — renouncing ownership would permanently lock funds
    function renounceOwnership() public pure override {
        revert InvalidAddress();
    }
}
