// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { Clones } from "@openzeppelin/contracts/proxy/Clones.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { Option } from "./Option.sol";
import { Redemption } from "./Redemption.sol";

using SafeERC20 for ERC20;


struct OptionParameter {
    address collateral_;
    address consideration_;
    uint40 expiration;
    uint96 strike;
    bool isPut;
}

contract OptionFactory is Ownable {
    address public redemptionClone;
    address public optionClone;
    uint64 public fee;

    uint256 public constant MAX_FEE = 0.01e18; // 1%

    error BlocklistedToken();
    error InvalidAddress();

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

    // Redemptions tracking - map used for security check in transferFrom()
    mapping(address => bool) private redemptions;

    // Blocklist for fee-on-transfer and rebasing tokens
    mapping(address => bool) public blocklist;

    constructor(address redemption_, address option_, uint64 fee_) Ownable(msg.sender) {
        require(fee_ <= MAX_FEE, "fee too high");
        redemptionClone = redemption_;
        optionClone = option_;
        fee = fee_;
    }

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

    function createOptions(OptionParameter[] memory optionParams) public {
        for (uint256 i = 0; i < optionParams.length; i++) {
            OptionParameter memory param = optionParams[i];
            createOption(param.collateral_, param.consideration_, param.expiration, param.strike, param.isPut);
        }
    }

    /**
     * @notice External function to transfer tokens using Permit2 or ERC20 allowance
     * @dev Only called by redemption contracts. Tries Permit2 first (modern UX), falls back to ERC20
     */
    function transferFrom(address from, address to, uint160 amount, address token) external returns (bool success) {
        // Only redemption contracts can call this (used in mint() and exercise())
        if (!redemptions[msg.sender]) revert InvalidAddress();
        ERC20(token).safeTransferFrom(from, to, amount);
        return true;
    }

    /// @notice Add a token to the blocklist (e.g., fee-on-transfer or rebasing tokens)
    /// @param token The token address to blocklist
    function blockToken(address token) external onlyOwner {
        if (token == address(0)) revert InvalidAddress();
        blocklist[token] = true;
        emit TokenBlocked(token, true);
    }

    /// @notice Remove a token from the blocklist
    /// @param token The token address to remove from blocklist
    function unblockToken(address token) external onlyOwner {
        blocklist[token] = false;
        emit TokenBlocked(token, false);
    }

    /// @notice Check if a token is blocklisted
    /// @param token The token address to check
    /// @return bool True if the token is blocklisted
    function isBlocked(address token) external view returns (bool) {
        return blocklist[token];
    }
}
