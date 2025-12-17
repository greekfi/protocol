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

using SafeERC20 for IERC20;

/// @notice Interface for factory contract token transfers
interface IFactory {
    function transferFrom(address from, address to, uint160 amount, address token) external;
}

/// @notice Token metadata structure
struct TokenData {
    address address_;
    string name;
    string symbol;
    uint8 decimals;
}

/// @notice Parameters for creating an option contract
struct OptionParameter {
    string optionSymbol;
    string redemptionSymbol;
    address collateral_;
    address consideration_;
    uint40 expiration;
    uint96 strike;
    bool isPut;
}

/// @notice Complete option information including all metadata
struct OptionInfo {
    TokenData option;
    TokenData redemption;
    TokenData collateral;
    TokenData consideration;
    OptionParameter p;
    address coll;
    address cons;
    uint256 expiration;
    uint256 strike;
    bool isPut;
}

/**
 * @title Redemption
 * @notice Represents the short position in an option contract (obligation to sell/buy)
 * @dev This is the "put" side that holds collateral and receives consideration when options are exercised.
 *      The contract is owned by the paired Option contract which coordinates lifecycle operations.
 *      Implements dual approval system supporting both standard ERC20 approvals and Permit2.
 *      After expiration, holders can redeem for remaining collateral or equivalent consideration.
 */
contract Redemption is ERC20, Ownable, ReentrancyGuardTransient, Initializable {
    // ============ STORAGE LAYOUT (OPTIMIZED FOR PACKING) ============

    // Account tracking removed for gas optimization
    // Users can sweep individual addresses or use off-chain indexing for batch sweep
    // address[] private _accounts;  // REMOVED: costs ~47k gas per new minter
    // mapping(address => bool) private accountsSet;  // REMOVED

    // Slot N: uint256 values (32 bytes each, separate slots)
    uint256 public fees;
    uint256 public strike;

    // Slot N+2: Packed slot (20 + 8 + 5 + 1 + 1 + 1 = 36 bytes - EXCEEDS 32, split needed)
    // Better: Pack addresses together, then small types together

    // Slot N+2: collateral (20 bytes) + consideration (20 bytes) - WAIT, 40 bytes total, needs 2 slots
    IERC20 public collateral; // 20 bytes - Slot N+2

    // Slot N+3: consideration (20 bytes) + _factory (20 bytes) - 40 bytes, needs 2 slots
    IERC20 public consideration; // 20 bytes - Slot N+3

    // Slot N+4: _factory (20 bytes) + fee (8 bytes) + expirationDate (5 bytes) = 33 bytes - SPLIT
    IFactory public _factory; // 20 bytes - Slot N+4
    uint64 public fee; // 8 bytes - Same slot as _factory

    // Slot N+5: expirationDate (5 bytes) + isPut (1 byte) + locked (1 byte) + consDecimals (1 byte) + collDecimals (1 byte) = 9 bytes - FITS!
    uint40 public expirationDate; // 5 bytes - New slot N+5
    bool public isPut; // 1 byte - Same slot
    bool public locked; // 1 byte - Same slot (defaults to false)
    uint8 consDecimals; // 1 byte - Same slot
    uint8 collDecimals; // 1 byte - Same slot
    // 23 bytes remaining in this slot

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
    error TokenBlocklisted();
    error ArithmeticOverflow();

    event ContractLocked();
    event ContractUnlocked();

    // ============ MODIFIERS ============

    /// @notice Ensures contract has expired
    modifier expired() {
        if (block.timestamp < expirationDate) revert ContractNotExpired();
        _;
    }

    /// @notice Ensures contract has not expired
    modifier notExpired() {
        if (block.timestamp >= expirationDate) revert ContractExpired();

        _;
    }

    /// @notice Validates that amount is non-zero
    /// @param amount The amount to validate
    modifier validAmount(uint256 amount) {
        if (amount == 0) revert InvalidValue();
        _;
    }

    /// @notice Validates that address is not zero
    /// @param addr The address to validate
    modifier validAddress(address addr) {
        if (addr == address(0)) revert InvalidAddress();
        _;
    }

    /// @notice Ensures account has sufficient redemption token balance
    /// @param contractHolder The account to check
    /// @param amount The required balance
    modifier sufficientBalance(address contractHolder, uint256 amount) {
        if (balanceOf(contractHolder) < amount) revert InsufficientBalance();
        _;
    }

    event Redeemed(address option, address token, address holder, uint256 amount);

    /// @notice Ensures contract is not locked
    modifier notLocked() {
        if (locked) revert LockedContract();
        _;
    }

    /// @notice Ensures account has sufficient collateral balance
    /// @param account The account to check
    /// @param amount The required collateral amount
    modifier sufficientCollateral(address account, uint256 amount) {
        if (collateral.balanceOf(account) < amount) revert InsufficientCollateral();
        _;
    }

    /// @notice Ensures account has sufficient consideration balance
    /// @param account The account to check
    /// @param amount The required amount (in collateral decimals, will be converted)
    modifier sufficientConsideration(address account, uint256 amount) {
        uint256 consAmount = toConsideration(amount);
        if (consideration.balanceOf(account) < consAmount) revert InsufficientConsideration();
        _;
    }

    // ============ CONSTRUCTOR & INITIALIZATION ============

    /**
     * @notice Constructor for template contract (used by clone factory)
     * @param name_ Token name (not used in clones)
     * @param symbol_ Token symbol (not used in clones)
     * @param collateral_ Collateral token address (not used in clones)
     * @param consideration_ Consideration token address (not used in clones)
     * @param expirationDate_ Expiration timestamp (not used in clones)
     * @param strike_ Strike price (not used in clones)
     * @param isPut_ Whether this is a put option (not used in clones)
     */
    constructor(
        string memory name_,
        string memory symbol_,
        address collateral_,
        address consideration_,
        uint256 expirationDate_,
        uint256 strike_,
        bool isPut_
    ) ERC20(name_, symbol_) Ownable(msg.sender) Initializable() { }

    /**
     * @notice Initializes a cloned redemption contract
     * @dev Called once after cloning by the factory. Sets all option parameters and ownership.
     * @param collateral_ Address of collateral token
     * @param consideration_ Address of consideration token (payment token)
     * @param expirationDate_ Unix timestamp of expiration
     * @param strike_ Strike price (18 decimal encoding)
     * @param isPut_ True for put option, false for call
     * @param option_ Address of the paired Option contract (becomes owner)
     * @param factory_ Address of the OptionFactory
     * @param fee_ Fee percentage (in 1e18 basis, max 1%)
     */
    function init(
        address collateral_,
        address consideration_,
        uint40 expirationDate_,
        uint256 strike_,
        bool isPut_,
        address option_,
        address factory_,
        uint64 fee_
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
        fee = fee_;
        consDecimals = IERC20Metadata(consideration_).decimals();
        collDecimals = IERC20Metadata(collateral_).decimals();
        _transferOwnership(option_);
    }

    // ============ MINTING FUNCTIONS ============

    /**
     * @notice Mints redemption tokens by depositing collateral
     * @dev Only callable by the paired Option contract during option minting.
     *      Pulls collateral from account, verifies no fee-on-transfer, mints tokens minus fees.
     * @param account Address to receive redemption tokens
     * @param amount Amount of collateral to deposit (in collateral token decimals)
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
        // Defense-in-depth: verify no fee-on-transfer despite factory blocklist
        uint256 balanceBefore = collateral.balanceOf(address(this));

        _factory.transferFrom(account, address(this), uint160(amount), address(collateral));

        // Verify full amount received (costs ~3.2k gas but provides important safety)
        if (collateral.balanceOf(address(this)) - balanceBefore != amount) {
            revert FeeOnTransferNotSupported();
        }

        // Calculate fee and mint (safe: max fee is 1%, can't overflow with unchecked)
        unchecked {
            uint256 fee_ = (amount * fee) / 1e18; // Inline fee calculation
            fees += fee_;
            _mint(account, amount - fee_);
        }
    }

    // ============ REDEEM FUNCTIONS ============

    /**
     * @notice Redeems all redemption tokens for an account (post-expiration)
     * @dev Burns all redemption tokens and returns collateral or equivalent consideration
     * @param account Address to redeem for
     */
    function redeem(address account) public notLocked {
        redeem(account, balanceOf(account));
    }

    /**
     * @notice Redeems specified amount for msg.sender (post-expiration)
     * @dev Burns redemption tokens and returns collateral or equivalent consideration
     * @param amount Amount of redemption tokens to burn
     */
    function redeem(uint256 amount) public notLocked {
        redeem(msg.sender, amount);
    }

    /**
     * @notice Redeems redemption tokens after expiration
     * @dev Burns tokens and returns collateral if available, otherwise equivalent consideration
     * @param account Address to redeem for
     * @param amount Amount of redemption tokens to burn
     */
    function redeem(address account, uint256 amount) public expired notLocked nonReentrant {
        _redeem(account, amount);
    }

    /**
     * @notice Redeems matched Option+Redemption pairs before expiration
     * @dev Only callable by the paired Option contract. Burns redemption tokens and returns collateral.
     * @param account Address to redeem for
     * @param amount Amount to redeem
     */
    function _redeemPair(address account, uint256 amount) public notExpired notLocked onlyOwner {
        _redeem(account, amount);
    }

    /**
     * @notice Internal redemption logic
     * @dev Burns tokens and sends collateral. If insufficient collateral, fulfills with consideration.
     * @param account Address to redeem for
     * @param amount Amount to redeem
     */
    function _redeem(address account, uint256 amount) internal sufficientBalance(account, amount) validAmount(amount) {
        uint256 balance = collateral.balanceOf(address(this));
        uint256 collateralToSend = amount <= balance ? amount : balance;

        _burn(account, collateralToSend);

        if (balance < amount) { // fulfill with consideration because not enough collateral
            _redeemConsideration(account, amount - balance);
        }

        if (collateralToSend > 0) { // Transfer remaining collateral afterwards
            collateral.safeTransfer(account, collateralToSend);
        }
        emit Redeemed(address(owner()), address(collateral), account, amount);
    }

    // ============ CONSIDERATION REDEEM FUNCTIONS ============

    /**
     * @notice Redeems redemption tokens for consideration instead of collateral (for msg.sender)
     * @dev Used when collateral is depleted. Burns redemption tokens and returns equivalent consideration.
     * @param amount Amount of redemption tokens to burn
     */
    function redeemConsideration(uint256 amount) public notLocked {
        redeemConsideration(msg.sender, amount);
    }

    /**
     * @notice Redeems redemption tokens for consideration instead of collateral
     * @dev Used when collateral is depleted. Burns tokens and sends equivalent consideration based on strike price.
     * @param account Address to redeem for
     * @param amount Amount of redemption tokens to burn
     */
    function redeemConsideration(address account, uint256 amount) public notLocked nonReentrant {
        _redeemConsideration(account, amount);
    }

    /**
     * @notice Internal logic for redeeming via consideration
     * @dev Calculates consideration amount based on strike price, burns redemption tokens, sends consideration
     * @param account Address to redeem for
     * @param amount Amount of redemption tokens to burn
     */
    function _redeemConsideration(address account, uint256 amount)
        internal
        sufficientBalance(account, amount)
        sufficientConsideration(address(this), amount)
        validAmount(amount)
    {
        _burn(account, amount);
        uint256 consAmount = toConsideration(amount);
        consideration.safeTransfer(account, consAmount);
        emit Redeemed(address(owner()), address(consideration), account, consAmount);
    }

    // ============ EXERCISE FUNCTION ============

    /**
     * @notice Handles option exercise by transferring collateral for consideration
     * @dev Only callable by paired Option contract. Pulls consideration from caller, sends collateral to account.
     * @param account Address to receive collateral
     * @param amount Amount of options being exercised
     * @param caller Address paying consideration (the option holder)
     */
    function exercise(address account, uint256 amount, address caller)
        public
        notExpired
        notLocked
        onlyOwner
        nonReentrant
        sufficientConsideration(caller, amount)
        sufficientCollateral(address(this), amount)
        validAmount(amount)
    {
        _factory.transferFrom(caller, address(this), uint160(toConsideration(amount)), address(consideration));
        collateral.safeTransfer(account, amount);
    }

    // ============ SWEEP FUNCTIONS ============

    /**
     * @notice Sweeps (redeems) all redemption tokens for a single holder after expiration
     * @dev Convenience function for post-expiration cleanup
     * @param holder Address to sweep redemption tokens for
     */
    function sweep(address holder) public expired notLocked nonReentrant {
        _redeem(holder, balanceOf(holder));
    }

    /**
     * @notice Batch sweep for multiple holders (requires off-chain account indexing)
     * @dev Pass array of holder addresses obtained from Transfer events or indexer.
     *      Skips addresses with zero balance.
     * @param holders Array of addresses to sweep
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

    /**
     * @notice Claims accumulated protocol fees
     * @dev Only callable by the factory. Transfers all accumulated fees to factory.
     */
    function claimFees() public onlyOwner nonReentrant {
        if (msg.sender != address(_factory)) {
            revert InvalidAddress();
        }
        collateral.safeTransfer(msg.sender, fees);
        fees = 0;
    }

    /**
     * @notice Locks the contract to prevent token transfers
     * @dev Only callable by owner (the paired Option contract)
     */
    function lock() public onlyOwner {
        locked = true;
    }

    /**
     * @notice Unlocks the contract to allow token transfers
     * @dev Only callable by owner (the paired Option contract)
     */
    function unlock() public onlyOwner {
        locked = false;
    }

    // Account tracking functions removed for gas optimization
    // Use off-chain indexing (graph protocol, event logs) to track holders

    // ============ CONVERSION FUNCTIONS ============

    /**
     * @notice Converts collateral amount to equivalent consideration amount based on strike price
     * @dev Handles decimal normalization between tokens with different decimals.
     *      Uses 512-bit multiplication to prevent overflow.
     * @param amount Amount in collateral decimals
     * @return Equivalent amount in consideration decimals
     */
    function toConsideration(uint256 amount) public view returns (uint256) {
        uint256 consMultiple = Math.mulDiv((10 ** consDecimals), strike, (10 ** STRIKE_DECIMALS) * (10 ** collDecimals));

        (uint256 high, uint256 low) = Math.mul512(amount, consMultiple);
        if (high != 0) {
            revert ArithmeticOverflow();
        }
        return low;
    }

    /**
     * @notice Converts consideration amount to equivalent collateral amount based on strike price
     * @dev Handles decimal normalization between tokens with different decimals.
     *      Uses 512-bit multiplication to prevent overflow.
     * @param consAmount Amount in consideration decimals
     * @return Equivalent amount in collateral decimals
     */
    function toCollateral(uint256 consAmount) public view returns (uint256) {
        uint256 collMultiple =
            Math.mulDiv((10 ** collDecimals) * (10 ** STRIKE_DECIMALS), 1, strike * (10 ** consDecimals));

        (uint256 high, uint256 low) = Math.mul512(consAmount, collMultiple);
        if (high != 0) {
            revert ArithmeticOverflow();
        }
        return low;
    }

    /**
     * @notice Calculates fee for a given amount
     * @dev Fee is calculated as (amount * fee) / 1e18
     * @param amount Amount to calculate fee for
     * @return Fee amount
     */
    function toFee(uint256 amount) public view returns (uint256) {
        return Math.mulDiv(fee, amount, 1e18);
    }

    // ============ METADATA FUNCTIONS ============

    /**
     * @notice Returns the redemption token name
     * @dev Dynamically generated as "{CollateralSymbol}-REDEM-{ExpirationTimestamp}"
     * @return Token name
     */
    function name() public view override returns (string memory) {
        return
            string(abi.encodePacked(IERC20Metadata(address(collateral)).symbol(), "-REDEM-", uint2str(expirationDate)));
    }

    /**
     * @notice Returns the redemption token symbol
     * @dev Same as name for this implementation
     * @return Token symbol
     */
    function symbol() public view override returns (string memory) {
        return name();
    }

    /**
     * @notice Returns the number of decimals for the redemption token
     * @dev Matches the collateral token decimals
     * @return Number of decimals
     */
    function decimals() public view override returns (uint8) {
        return collDecimals;
    }

    /**
     * @notice Returns metadata for the collateral token
     * @dev Queries the collateral token contract for name, symbol, decimals
     * @return TokenData struct with collateral token information
     */
    function collateralData() public view returns (TokenData memory) {
        IERC20Metadata collateralMetadata = IERC20Metadata(address(collateral));
        return TokenData(
            address(collateral), collateralMetadata.name(), collateralMetadata.symbol(), collateralMetadata.decimals()
        );
    }

    /**
     * @notice Returns metadata for the consideration token
     * @dev Queries the consideration token contract for name, symbol, decimals
     * @return TokenData struct with consideration token information
     */
    function considerationData() public view returns (TokenData memory) {
        IERC20Metadata considerationMetadata = IERC20Metadata(address(consideration));
        return TokenData(
            address(consideration),
            considerationMetadata.name(),
            considerationMetadata.symbol(),
            considerationMetadata.decimals()
        );
    }

    /**
     * @notice Returns the address of the paired Option contract
     * @dev The Option contract is the owner of this Redemption contract
     * @return Address of the Option contract
     */
    function option() public view returns (address) {
        return owner();
    }

    // ============ UTILITY FUNCTIONS ============

    /**
     * @notice Returns the minimum of two values
     * @param a First value
     * @param b Second value
     * @return Minimum of a and b
     */
    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    /**
     * @notice Returns the maximum of two values
     * @param a First value
     * @param b Second value
     * @return Maximum of a and b
     */
    function max(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? a : b;
    }

    /**
     * @notice Converts a uint256 to its string representation
     * @dev Used for generating token names with expiration timestamps
     * @param _i The number to convert
     * @return str The string representation of the number
     */
    function uint2str(uint256 _i) internal pure returns (string memory str) {
        if (_i == 0) {
            return "0";
        }
        uint256 j = _i;
        uint256 length;
        while (j != 0) {
            length++;
            j /= 10;
        }
        bytes memory bstr = new bytes(length);
        uint256 k = length;
        j = _i;
        while (j != 0) {
            bstr[--k] = bytes1(uint8(48 + j % 10));
            j /= 10;
        }
        str = string(bstr);
    }
}
