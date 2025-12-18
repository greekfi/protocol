// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { Clones } from "@openzeppelin/contracts/proxy/Clones.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { Option } from "./Option.sol";
import { Redemption } from "./Redemption.sol";

using SafeERC20 for ERC20;

/// @notice Parameters for creating an option contract
struct OptionParameter {
    address collateral_;
    address consideration_;
    uint40 expiration;
    uint96 strike;
    bool isPut;
}

/**
 * @title OptionFactory
 * @notice Factory contract for creating option pairs using minimal proxy clones (EIP-1167)
 * @dev Deploys gas-efficient minimal proxy clones of Option and Redemption template contracts.
 *      Maintains a blocklist for fee-on-transfer and rebasing tokens to prevent issues.
 *      Provides centralized token transfer functionality via transferFrom to support dual approval systems.
 */
contract OptionFactory is Ownable {
    // ============ STATE VARIABLES ============

    /// @notice Address of the Redemption template contract for cloning
    address public redemptionClone;

    /// @notice Address of the Option template contract for cloning
    address public optionClone;

    /// @notice Protocol fee percentage (in 1e18 basis)
    uint64 public fee;

    /// @notice Maximum allowed fee (1%)
    uint256 public constant MAX_FEE = 0.01e18; // 1%

    // ============ ERRORS ============

    error BlocklistedToken();
    error InvalidAddress();

    // ============ EVENTS ============

    event OptionCreated(
        address collateral,
        address consideration,
        uint256 expirationDate,
        uint256 strike,
        bool isPut,
        address option,
        address redemption
    );

    event TokenBlocked(address token, bool blocked);

    // ============ STORAGE MAPPINGS ============

    /// @notice Tracks valid redemption contracts for security in transferFrom()
    mapping(address => bool) private redemptions;

    /// @notice Blocklist for fee-on-transfer and rebasing tokens
    mapping(address => bool) public blocklist;

    // ============ CONSTRUCTOR ============

    /**
     * @notice Constructs the OptionFactory with template contracts and fee
     * @param redemption_ Address of the Redemption template contract
     * @param option_ Address of the Option template contract
     * @param fee_ Protocol fee percentage (must be <= MAX_FEE)
     */
    constructor(address redemption_, address option_, uint64 fee_) Ownable(msg.sender) {
        require(fee_ <= MAX_FEE, "fee too high");
        if (redemption_ == address(0) || option_ == address(0)) revert InvalidAddress();
        redemptionClone = redemption_;
        optionClone = option_;
        fee = fee_;
    }

    // ============ OPTION CREATION FUNCTIONS ============

    /**
     * @notice Creates a new option pair (Option + Redemption contracts)
     * @dev Clones template contracts, initializes them with parameters, and links them together.
     *      Checks that tokens are not blocklisted before deployment.
     *      Additional validation performed in the Option/Redemption init()
     * @param collateral Address of the collateral token (what backs the option)
     * @param consideration Address of the consideration token (payment for exercise)
     * @param expirationDate Unix timestamp when the option expires
     * @param strike Strike price (18 decimal encoding)
     * @param isPut True for put option, false for call option
     * @return Address of the created Option contract
     */
    function createOption(address collateral, address consideration, uint40 expirationDate, uint96 strike, bool isPut)
        public
        returns (address)
    {
        // Check blocklist for fee-on-transfer and rebasing tokens
        if (blocklist[collateral] || blocklist[consideration]) revert BlocklistedToken();

        address redemption_ = Clones.clone(redemptionClone);
        address option_ = Clones.clone(optionClone);

        Redemption redemption = Redemption(redemption_);
        Option option = Option(option_);

        redemption.init(collateral, consideration, expirationDate, strike, isPut, option_, address(this), fee);
        option.init(redemption_, msg.sender, fee);
        redemptions[redemption_] = true;

        emit OptionCreated(collateral, consideration, expirationDate, strike, isPut, option_, redemption_);
        return option_;
    }

    /**
     * @notice Batch creates multiple option pairs from an array of parameters
     * @dev Convenience function for deploying multiple options in a single transaction
     * @param optionParams Array of OptionParameter structs defining each option to create
     */
    function createOptions(OptionParameter[] memory optionParams) public {
        for (uint256 i = 0; i < optionParams.length; i++) {
            OptionParameter memory param = optionParams[i];
            createOption(param.collateral_, param.consideration_, param.expiration, param.strike, param.isPut);
        }
    }

    // ============ TOKEN TRANSFER FUNCTION ============

    /**
     * @notice Transfers tokens from one address to another using standard ERC20 approval
     * @dev Only callable by registered Redemption contracts. Used during mint() and exercise().
     *      Provides centralized transfer logic to support future dual approval systems.
     * @param from Address to transfer tokens from
     * @param to Address to transfer tokens to
     * @param amount Amount of tokens to transfer
     * @param token Address of the token to transfer
     * @return success True if transfer succeeded
     */
    function transferFrom(address from, address to, uint160 amount, address token) external returns (bool success) {
        // Only redemption contracts can call this (used in mint() and exercise())
        if (!redemptions[msg.sender]) revert InvalidAddress();
        ERC20(token).safeTransferFrom(from, to, amount);
        return true;
    }

    // ============ BLOCKLIST MANAGEMENT FUNCTIONS ============

    /**
     * @notice Adds a token to the blocklist. Cannot be used as collateral nor consideration.
     * @dev Prevents creation of new options using this token. Use for fee-on-transfer or rebasing tokens.
     *      Only callable by owner.
     * @param token The token address to blocklist
     */
    function blockToken(address token) external onlyOwner {
        if (token == address(0)) revert InvalidAddress();
        blocklist[token] = true;
        emit TokenBlocked(token, true);
    }

    /**
     * @notice Removes a token from the blocklist
     * @dev Re-enables option creation using this token. Only callable by owner.
     * @param token The token address to remove from blocklist
     */
    function unblockToken(address token) external onlyOwner {
        blocklist[token] = false;
        emit TokenBlocked(token, false);
    }

    /**
     * @notice Checks if a token is blocklisted
     * @param token The token address to check
     * @return True if the token is blocklisted, false otherwise
     */
    function isBlocked(address token) external view returns (bool) {
        return blocklist[token];
    }

    /**
     * @notice Transfers fees to the owner
     * @param token The token address to transfer
     */
    function claimFees(address token) public onlyOwner {
        ERC20 token_ = ERC20(token);
        uint256 amount = token_.balanceOf(address(this));
        token_.transfer(owner(), amount);
    }
}
