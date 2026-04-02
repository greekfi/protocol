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

/// @notice Interface for factory contract token transfers
interface IFactory {
    function transferFrom(address from, address to, uint160 amount, address token) external;
}

/**
 * @title Redemption
 * @notice Short position ERC20 in an option contract — represents the obligation side
 * @dev Deployed as EIP-1167 minimal proxy clones via OptionFactory. Owned by the paired
 *      Option contract which coordinates all lifecycle operations.
 *
 *      Holds all collateral and receives consideration when options are exercised.
 *      After expiration, holders redeem for pro-rata collateral + consideration.
 *
 *      Rounding policy: round DOWN on all payouts (toConsideration), round UP on all
 *      collections (toNeededConsideration in exercise). Dust stays in the protocol.
 *
 *      Post-expiry redemption paths:
 *        - redeem(): pro-rata collateral + consideration for remainder
 *        - redeemConsideration(): consideration at strike price (alternative path, by design)
 */
contract Redemption is ERC20, Ownable, ReentrancyGuardTransient, Initializable {
    // ============ STORAGE LAYOUT (OPTIMIZED FOR PACKING) ============

    // Slot N: uint256 values (32 bytes each, separate slots)
    uint256 public strike;

    // Slot N+2: address (20 bytes)
    IERC20 public collateral;

    // Slot N+3: address (20 bytes)
    IERC20 public consideration;

    // Slot N+4: _factory (20 bytes)
    IFactory public _factory;

    // Slot N+5: expirationDate (5) + isPut (1) + locked (1) + consDecimals (1) + collDecimals (1) = 9 bytes
    uint40 public expirationDate;
    bool public isPut;
    bool public locked; // Emergency pause flag (defaults to false)
    uint8 public consDecimals;
    uint8 public collDecimals;

    uint8 public constant STRIKE_DECIMALS = 18; // Not stored (constant)

    // ============ END STORAGE LAYOUT ============

    error ContractNotExpired();
    error ContractExpired();
    error InsufficientBalance();
    error InvalidValue();
    error InvalidAddress();
    error LockedContract();
    error FeeOnTransferNotSupported();
    error InsufficientCollateral();
    error InsufficientConsideration();
    error ArithmeticOverflow();

    // ============ MODIFIERS ============

    /// @notice Requires option to have expired
    modifier expired() {
        if (block.timestamp < expirationDate) revert ContractNotExpired();
        _;
    }

    /// @notice Requires option to not have expired
    modifier notExpired() {
        if (block.timestamp >= expirationDate) revert ContractExpired();

        _;
    }

    /// @notice Reverts if amount is zero
    modifier validAmount(uint256 amount) {
        if (amount == 0) revert InvalidValue();
        _;
    }

    /// @notice Reverts if address is zero
    modifier validAddress(address addr) {
        if (addr == address(0)) revert InvalidAddress();
        _;
    }

    /// @notice Reverts if account's Redemption balance < amount
    modifier sufficientBalance(address account, uint256 amount) {
        if (balanceOf(account) < amount) revert InsufficientBalance();
        _;
    }

    event Redeemed(address option, address token, address holder, uint256 amount);

    /// @notice Reverts if contract is locked (emergency pause)
    modifier notLocked() {
        if (locked) revert LockedContract();
        _;
    }

    /// @notice Reverts if available collateral < amount
    modifier sufficientCollateral(uint256 amount) {
        if (collateral.balanceOf(address(this)) < amount) revert InsufficientCollateral();
        _;
    }

    /// @notice Reverts if account lacks enough consideration (floor-rounded conversion)
    modifier sufficientConsideration(address account, uint256 amount) {
        uint256 consAmount = toConsideration(amount);
        if (consideration.balanceOf(account) < consAmount) revert InsufficientConsideration();
        _;
    }

    // ============ CONSTRUCTOR & INITIALIZATION ============

    /**
     * @notice Template constructor — only used for the implementation contract
     * @dev Clones never execute the constructor; state is set via init().
     *      Calls _disableInitializers() to prevent init() on the template itself.
     */
    constructor(
        string memory name_,
        string memory symbol_,
        address collateral_,
        address consideration_,
        uint256 expirationDate_,
        uint256 strike_,
        bool isPut_
    ) ERC20(name_, symbol_) Ownable(msg.sender) Initializable() {
        _disableInitializers();
    }

    /**
     * @notice Initializes a cloned Redemption contract
     * @dev Called exactly once by OptionFactory.createOption() immediately after cloning.
     *      Sets all option parameters, caches token decimals, and transfers ownership to the Option contract.
     * @param collateral_ Collateral token (what backs the option)
     * @param consideration_ Consideration token (payment for exercise)
     * @param expirationDate_ Unix timestamp when the option expires
     * @param strike_ Strike price (18-decimal fixed-point encoding)
     * @param isPut_ True for put, false for call
     * @param option_ Paired Option contract (becomes owner)
     * @param factory_ OptionFactory address
     */
    function init(
        address collateral_,
        address consideration_,
        uint40 expirationDate_,
        uint256 strike_,
        bool isPut_,
        address option_,
        address factory_
    ) public initializer {
        if (collateral_ == address(0)) revert InvalidAddress();
        if (consideration_ == address(0)) revert InvalidAddress();
        if (factory_ == address(0)) revert InvalidAddress();
        if (strike_ == 0) revert InvalidValue();
        if (expirationDate_ < block.timestamp) revert InvalidValue();

        collateral = IERC20(collateral_);
        consideration = IERC20(consideration_);
        expirationDate = expirationDate_;
        strike = strike_;
        isPut = isPut_;
        _factory = IFactory(factory_);
        consDecimals = IERC20Metadata(consideration_).decimals();
        collDecimals = IERC20Metadata(collateral_).decimals();
        _transferOwnership(option_);
    }

    // ============ MINTING FUNCTIONS ============

    /**
     * @notice Mints Redemption tokens by depositing collateral (1:1, no fees)
     * @dev Only callable by the paired Option contract. Pulls collateral from `account` via
     *      factory.transferFrom(), verifies no fee-on-transfer.
     * @param account Address to receive Redemption tokens (and whose collateral is pulled)
     * @param amount Collateral to deposit (in collateral token decimals)
     */
    function mint(address account, uint256 amount)
        public
        onlyOwner
        notExpired
        notLocked
        nonReentrant
        validAmount(amount)
        validAddress(account)
    {
        // Ensure amount fits in uint160 for Permit2 compatibility
        if (amount > type(uint160).max) revert ArithmeticOverflow();

        // Defense-in-depth: verify no fee-on-transfer despite factory blocklist
        uint256 balanceBefore = collateral.balanceOf(address(this));

        // forge-lint: disable-next-line(unsafe-typecast)
        _factory.transferFrom(account, address(this), uint160(amount), address(collateral));

        // Verify full amount received
        if (collateral.balanceOf(address(this)) - balanceBefore != amount) {
            revert FeeOnTransferNotSupported();
        }

        _mint(account, amount);
    }

    // ============ REDEEM FUNCTIONS ============

    /// @notice Redeems ALL Redemption tokens for `account` (post-expiry, permissionless)
    function redeem(address account) public notLocked {
        redeem(account, balanceOf(account));
    }

    /// @notice Redeems `amount` Redemption tokens for msg.sender (post-expiry)
    function redeem(uint256 amount) public notLocked {
        redeem(msg.sender, amount);
    }

    /**
     * @notice Post-expiry pro-rata redemption
     * @dev Distributes: collateral_share = amount * collateralBalance / totalSupply (rounds DOWN),
     *      remainder converted to consideration at strike (rounds DOWN).
     *      Every redeemer gets the same rate — no first-redeemer advantage.
     *      Holders may alternatively use redeemConsideration() post-expiry to receive
     *      consideration at strike price instead of pro-rata collateral.
     * @param account Address to redeem for (permissionless post-expiry)
     * @param amount Redemption tokens to burn
     */
    function redeem(address account, uint256 amount) public expired notLocked nonReentrant {
        _redeem(account, amount);
    }

    /**
     * @notice Pre-expiry pair redeem — burns Redemption tokens and returns collateral
     * @dev Only callable by the paired Option contract (which also burns the Option tokens).
     *      Waterfall: collateral first, consideration fallback as defense-in-depth.
     *      Under normal operations, the waterfall never triggers because
     *      available_collateral == total_option_supply (invariant).
     */
    function _redeemPair(address account, uint256 amount) public notExpired notLocked onlyOwner nonReentrant {
        _redeemPairInternal(account, amount);
    }

    /**
     * @notice Internal post-expiry pro-rata redemption logic
     * @dev collateralToSend = mulDiv(amount, collateralBalance, totalSupply) — rounds DOWN.
     *      remainder = amount - collateralToSend → converted to consideration (rounds DOWN).
     *      Dust stays in the contract.
     */
    function _redeem(address account, uint256 amount) internal sufficientBalance(account, amount) validAmount(amount) {
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
            consideration.safeTransfer(account, consToSend);
        }
        emit Redeemed(address(owner()), address(collateral), account, collateralToSend);
    }

    /**
     * @notice Internal pre-expiry waterfall redemption for matched pairs
     * @dev Collateral first, consideration fallback (defense-in-depth — should never trigger).
     */
    function _redeemPairInternal(address account, uint256 amount)
        internal
        sufficientBalance(account, amount)
        validAmount(amount)
    {
        // Waterfall: collateral first, consideration fallback.
        // Under normal operations collateral always covers `amount` because
        // available_collateral == total_option_supply. This fallback exists
        // as defense-in-depth if the collateral token misbehaves.
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

    // ============ CONSIDERATION REDEEM FUNCTIONS ============

    /**
     * @notice Redeems Redemption tokens for consideration at strike price
     * @dev Burns caller's tokens and returns equivalent consideration (rounds DOWN).
     *      Callable both before and after expiration — no expiry restriction by design.
     *      Post-expiry, this is an alternative to redeem() which distributes pro-rata collateral.
     *      Both paths are available so holders can choose the most favorable redemption route.
     *      Only msg.sender can redeem their own tokens to prevent forced position closure.
     * @param amount Redemption tokens to burn
     */
    function redeemConsideration(uint256 amount) public notLocked nonReentrant {
        _redeemConsideration(msg.sender, amount);
    }

    /**
     * @notice Internal: burns Redemption tokens, sends consideration at strike conversion rate
     * @dev Conversion uses toConsideration (rounds DOWN — dust stays in protocol).
     */
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

    // ============ EXERCISE FUNCTION ============

    /**
     * @notice Handles option exercise — swaps consideration for collateral
     * @dev Only callable by the paired Option contract. Pulls consideration from `caller`
     *      using toNeededConsideration (rounds UP — exerciser pays at most 1 extra wei),
     *      sends collateral to `account`.
     * @param account Recipient of the collateral
     * @param amount Collateral units to send (= number of options exercised)
     * @param caller Address paying consideration (the option holder)
     */
    function exercise(address account, uint256 amount, address caller)
        public
        notExpired
        notLocked
        onlyOwner
        nonReentrant
        sufficientCollateral(amount)
        validAmount(amount)
    {
        uint256 consAmount = toNeededConsideration(amount);
        if (consideration.balanceOf(caller) < consAmount) revert InsufficientConsideration();
        if (consAmount == 0) revert InvalidValue();
        // Ensure consideration amount fits in uint160 for Permit2 compatibility
        if (consAmount > type(uint160).max) revert ArithmeticOverflow();

        uint256 consBefore = consideration.balanceOf(address(this));
        // forge-lint: disable-next-line(unsafe-typecast)
        _factory.transferFrom(caller, address(this), uint160(consAmount), address(consideration));
        if (consideration.balanceOf(address(this)) - consBefore < consAmount) revert FeeOnTransferNotSupported();
        collateral.safeTransfer(account, amount);
    }

    // ============ SWEEP FUNCTIONS ============

    /**
     * @notice Sweeps all Redemption tokens for a single holder (post-expiry, permissionless)
     * @dev Funds go to the holder, not the caller. Safe because post-expiry there is no
     *      advantage to delaying redemption.
     */
    function sweep(address holder) public expired notLocked nonReentrant {
        uint256 amount = balanceOf(holder);
        if (amount > 0) {
            _redeem(holder, amount);
        }
    }

    /**
     * @notice Batch sweep for multiple holders (post-expiry, permissionless)
     * @dev Pass holder addresses obtained from Transfer events or off-chain indexer.
     *      Skips zero-balance addresses.
     */
    function sweep(address[] calldata holders) public expired notLocked nonReentrant {
        for (uint256 i = 0; i < holders.length; i++) {
            address holder = holders[i];
            uint256 balance = balanceOf(holder);
            if (balance > 0) {
                _redeem(holder, balance);
            }
        }
    }

    // ============ ADMIN FUNCTIONS ============

    /// @notice Emergency pause — called by Option.lock()
    function lock() public onlyOwner {
        locked = true;
    }

    /// @notice Unpause — called by Option.unlock()
    function unlock() public onlyOwner {
        locked = false;
    }

    // ============ CONVERSION FUNCTIONS ============

    /**
     * @notice Converts collateral amount to consideration at strike price (rounds DOWN)
     * @dev Used for payouts. Dust stays in the protocol.
     *      Formula: amount * strike * 10^consDecimals / (10^18 * 10^collDecimals)
     * @param amount Amount in collateral decimals
     * @return Equivalent consideration amount (rounded down)
     */
    function toConsideration(uint256 amount) public view returns (uint256) {
        return Math.mulDiv(amount, strike * (10 ** consDecimals), (10 ** STRIKE_DECIMALS) * (10 ** collDecimals));
    }

    /**
     * @notice Converts collateral amount to consideration at strike price (rounds UP)
     * @dev Used when collecting consideration (exercise) to ensure the protocol always
     *      has enough to cover all future redemptions. Exerciser pays at most 1 extra wei.
     * @param amount Amount in collateral decimals
     * @return Equivalent consideration amount (rounded up)
     */
    function toNeededConsideration(uint256 amount) public view returns (uint256) {
        return Math.mulDiv(
            amount, strike * (10 ** consDecimals), (10 ** STRIKE_DECIMALS) * (10 ** collDecimals), Math.Rounding.Ceil
        );
    }

    /**
     * @notice Converts consideration amount to collateral at strike price (rounds DOWN)
     * @param consAmount Amount in consideration decimals
     * @return Equivalent collateral amount
     */
    function toCollateral(uint256 consAmount) public view returns (uint256) {
        return Math.mulDiv(consAmount, (10 ** collDecimals) * (10 ** STRIKE_DECIMALS), strike * (10 ** consDecimals));
    }


    // ============ METADATA FUNCTIONS ============

    /**
     * @notice Dynamic token name: ROPT-{COLL}-{CONS}-{STRIKE}-{YYYY-MM-DD}
     * @dev For puts, strike is displayed as 1/strike (human-readable price)
     */
    function name() public view override returns (string memory) {
        // For put options, display inverted price (1/strike)
        uint256 displayStrike = isPut ? (1e36 / strike) : strike;

        return string(
            abi.encodePacked(
                "ROPT-",
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

    /// @notice Token symbol (same as name)
    function symbol() public view override returns (string memory) {
        return name();
    }

    /// @notice Decimals match the collateral token
    function decimals() public view override returns (uint8) {
        return collDecimals;
    }

    /// @notice Collateral token metadata (name, symbol, decimals, address)
    function collateralData() public view returns (TokenData memory) {
        IERC20Metadata collateralMetadata = IERC20Metadata(address(collateral));
        return TokenData({
            address_: address(collateral),
            name: collateralMetadata.name(),
            symbol: collateralMetadata.symbol(),
            decimals: collateralMetadata.decimals()
        });
    }

    /// @notice Consideration token metadata (name, symbol, decimals, address)
    function considerationData() public view returns (TokenData memory) {
        IERC20Metadata considerationMetadata = IERC20Metadata(address(consideration));
        return TokenData({
            address_: address(consideration),
            name: considerationMetadata.name(),
            symbol: considerationMetadata.symbol(),
            decimals: considerationMetadata.decimals()
        });
    }

    /// @notice Address of the paired Option contract (= owner)
    function option() public view returns (address) {
        return owner();
    }

    /// @notice Address of the OptionFactory
    function factory() public view returns (address) {
        return address(_factory);
    }
}
