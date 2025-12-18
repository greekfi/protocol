// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

// import { OptionBase, OptionInfo, TokenData } from "./OptionBase.sol";
import { Redemption } from "./Redemption.sol";

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { Initializable } from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import { ReentrancyGuardTransient } from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";
import { IERC20, ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

using SafeERC20 for IERC20;

/// @notice Token metadata structure
struct TokenData {
    address address_;
    string name;
    string symbol;
    uint8 decimals;
}

/// @notice Balance information for an account across all related tokens
struct Balances {
    uint256 collateral;
    uint256 consideration;
    uint256 option;
    uint256 redemption;
}

/// @notice Complete option contract information including all parameters and token data
struct OptionInfo {
    address option;
    address redemption;
    TokenData collateral;
    TokenData consideration;
    uint256 expiration;
    uint256 strike;
    bool isPut;
}

/**
 * @title Option
 * @notice Represents the long position in an option contract (right to buy/sell)
 * @dev This is the "call" side of the option that gives holders the right to exercise.
 *      The contract owns the paired Redemption contract and coordinates all option lifecycle operations.
 *      Implements auto-settling transfers: transferring more options than owned triggers auto-mint,
 *      and receiving options while holding redemptions triggers auto-redeem.
 */
contract Option is ERC20, Ownable, ReentrancyGuardTransient, Initializable {
    Redemption public redemption;
    uint64 public fee;
    string private _tokenName;
    string private _tokenSymbol;

    event Mint(address longOption, address holder, uint256 amount);
    event Exercise(address longOption, address holder, uint256 amount);

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

    /// @notice Ensures contract is not locked
    modifier notLocked() {
        if (redemption.locked()) revert LockedContract();
        _;
    }

    /// @notice Ensures contract has not expired
    modifier notExpired() {
        if (block.timestamp >= expirationDate()) revert ContractExpired();

        _;
    }

    /// @notice Validates that amount is non-zero
    /// @param amount The amount to validate
    modifier validAmount(uint256 amount) {
        if (amount == 0) revert InvalidValue();
        _;
    }

    /// @notice Validates that address is not zero
    /// @param account The address to validate
    modifier validAddress(address account) {
        if (account == address(0)) revert InvalidAddress();
        _;
    }

    /// @notice Ensures account has sufficient balance
    /// @param contractHolder The account to check
    /// @param amount The required balance
    modifier sufficientBalance(address contractHolder, uint256 amount) {
        if (balanceOf(contractHolder) < amount) revert InsufficientBalance();
        _;
    }

    // ============ CONSTRUCTOR & INITIALIZATION ============

    /**
     * @notice Constructor for template contract (used by clone factory)
     * @param name_ Token name (not used in clones)
     * @param symbol_ Token symbol (not used in clones)
     * @param redemption__ Address of redemption contract
     */
    constructor(string memory name_, string memory symbol_, address redemption__)
        ERC20(name_, symbol_)
        Ownable(msg.sender)
    {
        redemption = Redemption(redemption__);
    }

    /**
     * @notice Initializes a cloned option contract
     * @dev Called once after cloning by the factory
     * @param redemption_ Address of the paired Redemption contract
     * @param owner Address that will own this option contract
     * @param fee_ Fee percentage (in 1e18 basis, max 1%)
     */
    function init(address redemption_, address owner, uint64 fee_) public initializer {
        if (redemption_ == address(0) || owner == address(0)) revert InvalidAddress();

        _transferOwnership(owner);
        redemption = Redemption(redemption_);
        fee = fee_;
    }

    // ============ VIEW FUNCTIONS ============

    /**
     * @notice Returns the token name
     * @dev Returns empty string as name is dynamically generated by frontend
     * @return Empty string
     */
    function name() public view override returns (string memory) {
        return string(
            abi.encodePacked(
                "OPT-",
                IERC20Metadata(address(collateral())).symbol(),
                "-",
                IERC20Metadata(address(consideration())).symbol(),
                "-",
                strike2str(strike()),
                "-",
                epoch2str(expirationDate())
            )
        );
    }

    /**
     * @notice Returns the token symbol
     * @dev Returns empty string as symbol is dynamically generated by frontend
     * @return Empty string
     */
    function symbol() public view override returns (string memory) {
        return name();
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

    /**
     * @notice Converts a uint96 10**18 based strike to its string representation
     * @dev Used for generating token names with strike prices
     *      The ideally we check for the largest digit and represent accordingly
     *      i.e. 1000e18 -> "1000", .01e18 -> "0.01"
     * @param _i The number to convert (in 18 decimal format)
     * @return str The string representation of the number
     */
    function strike2str(uint256 _i) internal pure returns (string memory str) {
        uint256 whole = _i / 1e18;
        uint256 fractional = _i % 1e18;

        // If no fractional part, return just the whole number
        if (fractional == 0) {
            return uint2str(whole);
        }

        // Convert fractional part to 18-digit string (with leading zeros)
        bytes memory fracBytes = new bytes(18);
        for (uint256 i = 18; i > 0; i--) {
            fracBytes[i - 1] = bytes1(uint8(48 + fractional % 10));
            fractional /= 10;
        }

        // Remove trailing zeros from fractional part
        uint256 len = 18;
        while (len > 0 && fracBytes[len - 1] == "0") {
            len--;
        }

        // If all fractional digits were zeros (shouldn't happen due to check above)
        if (len == 0) {
            return uint2str(whole);
        }

        // Copy non-zero fractional digits to result
        bytes memory fracResult = new bytes(len);
        for (uint256 i = 0; i < len; i++) {
            fracResult[i] = fracBytes[i];
        }

        // Concatenate whole part + decimal point + fractional part
        return string(abi.encodePacked(uint2str(whole), ".", string(fracResult)));
    }

    /**
     * @notice Converts a uint40 epoch time to ISO representation YYYY-MM-DD
     * @dev Used for generating token names with expiration timestamps
     * @param _i The number/time to convert
     * @return str The string representation of the number
     */
    function epoch2str(uint256 _i) internal pure returns (string memory str) {
        // Convert timestamp to days since epoch
        uint256 daysSinceEpoch = _i / 86400; // 86400 seconds per day

        // Calculate year
        uint256 year = 1970;
        uint256 daysInYear;

        while (true) {
            daysInYear = isLeapYear(year) ? 366 : 365;
            if (daysSinceEpoch >= daysInYear) {
                daysSinceEpoch -= daysInYear;
                year++;
            } else {
                break;
            }
        }

        // Calculate month and day
        uint256 month = 1;
        uint256[12] memory daysInMonth = [uint256(31), 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];

        // Adjust February for leap year
        if (isLeapYear(year)) {
            daysInMonth[1] = 29;
        }

        for (uint256 i = 0; i < 12; i++) {
            if (daysSinceEpoch >= daysInMonth[i]) {
                daysSinceEpoch -= daysInMonth[i];
                month++;
            } else {
                break;
            }
        }

        uint256 day = daysSinceEpoch + 1; // Days are 1-indexed

        // Format as YYYY-MM-DD
        return string(
            abi.encodePacked(
                uint2str(year),
                "-",
                month < 10 ? string(abi.encodePacked("0", uint2str(month))) : uint2str(month),
                "-",
                day < 10 ? string(abi.encodePacked("0", uint2str(day))) : uint2str(day)
            )
        );
    }

    /**
     * @notice Checks if a year is a leap year
     * @param year The year to check
     * @return True if the year is a leap year
     */
    function isLeapYear(uint256 year) internal pure returns (bool) {
        if (year % 4 != 0) return false;
        if (year % 100 != 0) return true;
        if (year % 400 != 0) return false;
        return true;
    }

    /**
     * @notice Returns the collateral token address
     * @dev Delegates to the Redemption contract
     * @return Address of the collateral token
     */
    function collateral() public view returns (address) {
        return address(redemption.collateral());
    }

    /**
     * @notice Returns the consideration token address
     * @dev Delegates to the Redemption contract
     * @return Address of the consideration token (payment token for exercise)
     */
    function consideration() public view returns (address) {
        return address(redemption.consideration());
    }

    /**
     * @notice Returns the expiration timestamp
     * @dev Delegates to the Redemption contract
     * @return Unix timestamp of option expiration
     */
    function expirationDate() public view returns (uint256) {
        return redemption.expirationDate();
    }

    /**
     * @notice Returns the strike price
     * @dev Delegates to the Redemption contract. Strike is encoded with 18 decimals
     * @return Strike price (18 decimal encoding)
     */
    function strike() public view returns (uint256) {
        return redemption.strike();
    }

    /**
     * @notice Returns whether this is a put option
     * @dev Delegates to the Redemption contract
     * @return True if put option, false if call option
     */
    function isPut() public view returns (bool) {
        return redemption.isPut();
    }

    // ============ MINTING FUNCTIONS ============

    /**
     * @notice Creates new option + redemption token pairs for msg.sender
     * @dev Deposits collateral and mints equal amounts of Option and Redemption tokens
     * @param amount Amount of collateral to deposit (in collateral token decimals)
     */
    function mint(uint256 amount) public notLocked {
        mint(msg.sender, amount);
    }

    /**
     * @notice Creates new option + redemption token pairs for a specified account
     * @dev Deposits collateral from msg.sender and mints tokens to account
     * @param account The recipient of the minted option and redemption tokens
     * @param amount Amount of collateral to deposit (in collateral token decimals)
     */
    function mint(address account, uint256 amount) public notLocked nonReentrant {
        mint_(account, amount);
    }

    /**
     * @notice Internal minting logic
     * @dev First mints Redemption tokens (which pulls collateral), then mints Option tokens minus fees
     * @param account The recipient of tokens
     * @param amount Amount of tokens to mint (before fees)
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
     * @notice Transfers option tokens from one address to another with auto-redeem
     * @dev After transfer, automatically redeems any matching Option+Redemption pairs the recipient holds
     * @param from Address to transfer from
     * @param to Address to transfer to
     * @param amount Amount to transfer
     * @return success True if transfer succeeded
     */
    function transferFrom(address from, address to, uint256 amount)
        public
        override
        notLocked
        nonReentrant
        returns (bool success)
    {
        success = super.transferFrom(from, to, amount);
        uint256 balance = redemption.balanceOf(to);
        if (balance > 0) {
            redeem_(to, min(balance, amount));
        }
    }

    /**
     * @notice Transfers option tokens with auto-mint and auto-redeem
     * @dev If sender lacks sufficient balance, auto-mints the difference.
     *      This should be treated like sending Collateral. The UX is
     *      designed like this to make the operation seamless when swapping
     *      Options in a single transfer/swap call.
     *      After transfer, auto-redeems any matching pairs the recipient holds.
     *      Auto-redemption is for the fact that you should always cancel out the
     *      "short" position in the option with the "long" and return back to
     *      just the collateral.
     * @param to Address to transfer to
     * @param amount Amount to transfer
     * @return success True if transfer succeeded
     */
    function transfer(address to, uint256 amount)
        public
        override
        notLocked
        nonReentrant
        validAddress(to)
        returns (bool success)
    {
        uint256 balance = balanceOf(msg.sender);
        if (balance < amount) {
            mint_(msg.sender, amount - balance);
        }

        success = super.transfer(to, amount);
        require(success, "Transfer failed");

        balance = redemption.balanceOf(to);
        if (balance > 0) {
            redeem_(to, min(balance, amount));
        }
    }

    // ============ EXERCISE FUNCTIONS ============

    /**
     * @notice Exercises options for msg.sender
     * @dev Burns Option tokens, pays consideration, receives collateral
     * @param amount Amount of options to exercise
     */
    function exercise(uint256 amount) public notLocked {
        exercise(msg.sender, amount);
    }

    /**
     * @notice Exercises options and sends collateral to specified account
     * @dev Burns caller's Option tokens, pulls consideration from caller, sends collateral to account
     * @param account Address to receive the collateral
     * @param amount Amount of options to exercise
     */
    function exercise(address account, uint256 amount) public notExpired notLocked nonReentrant validAmount(amount) {
        _burn(msg.sender, amount);
        redemption.exercise(account, amount, msg.sender);
        emit Exercise(address(this), msg.sender, amount);
    }

    // ============ REDEEM FUNCTIONS ============

    /**
     * @notice Redeems matched Option+Redemption pairs for msg.sender
     * @dev Burns both Option and Redemption tokens, returns collateral (pre-expiration only)
     * @param amount Amount of pairs to redeem
     */
    function redeem(uint256 amount) public notLocked {
        redeem(msg.sender, amount);
    }

    /**
     * @notice Redeems matched Option+Redemption pairs for specified account
     * @dev Burns both token types from account and returns collateral
     * @param account Account to redeem from
     * @param amount Amount of pairs to redeem
     */
    function redeem(address account, uint256 amount) public notLocked nonReentrant {
        redeem_(account, amount);
    }

    /**
     * @notice Internal redeem logic
     * @dev Burns Option tokens and calls Redemption contract to burn Redemption tokens and return collateral
     * @param account Account to redeem from
     * @param amount Amount to redeem
     */
    function redeem_(address account, uint256 amount) internal notExpired sufficientBalance(account, amount) {
        _burn(account, amount);
        redemption._redeemPair(account, amount);
    }

    // ============ QUERY FUNCTIONS ============

    /**
     * @notice Returns all token balances for an account
     * @dev Queries balances of collateral, consideration, option, and redemption tokens
     * @param account Address to query
     * @return Balances struct containing all four token balances
     */
    function balancesOf(address account) public view returns (Balances memory) {
        return Balances({
            collateral: IERC20(collateral()).balanceOf(account),
            consideration: IERC20(consideration()).balanceOf(account),
            option: balanceOf(account),
            redemption: redemption.balanceOf(account)
        });
    }

    /**
     * @notice Returns complete option contract information
     * @dev Aggregates all option parameters and token metadata into a single struct
     * @return OptionInfo struct with complete contract details
     */
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
            collateral: TokenData(coll, collMeta.name(), collMeta.symbol(), collMeta.decimals()),
            consideration: TokenData(cons, consMeta.name(), consMeta.symbol(), consMeta.decimals()),
            expiration: exp,
            strike: stk,
            isPut: put
        });
    }

    // ============ ADMIN FUNCTIONS ============

    /**
     * @notice Locks the contract to prevent transfers
     * @dev Only owner can call. Prevents all token transfers until unlocked
     */
    function lock() public onlyOwner {
        redemption.lock();
        emit ContractLocked();
    }

    /**
     * @notice Unlocks the contract to allow transfers
     * @dev Only owner can call. Re-enables token transfers
     */
    function unlock() public onlyOwner {
        redemption.unlock();
        emit ContractUnlocked();
    }

    /**
     * @notice adjusts fee for protocol
     * @dev Only Owner can adjust via Option. Fee is calculated as (amount * fee) / 1e18
     * @param fee_ Fee amount in 1e18 basis
     */
    function adjustFee(uint64 fee_) public onlyOwner {
        redemption.adjustFee(fee_);
    }

    /**
     * @notice Claims accumulated protocol fees
     * @dev Only callable by the factory. Transfers all accumulated fees to factory.
     */
    function claimFees() public onlyOwner nonReentrant {
        redemption.claimFees();
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
}
