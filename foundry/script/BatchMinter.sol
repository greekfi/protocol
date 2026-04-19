// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { IOption } from "../contracts/interfaces/IOption.sol";

/// @title BatchMinter
/// @notice Mints on multiple Greek Protocol options in a single transaction
/// @dev Before calling batchMint, user must:
///      1. Approve WETH to the OptionFactory (ERC20 approve)
///      2. Call factory.approve(weth, totalAmount)
contract BatchMinter {
    error ArrayLengthMismatch();
    error ZeroAddress();
    error ZeroAmount();

    event BatchMintExecuted(address indexed caller, uint256 optionCount, uint256 totalAmount);

    /// @notice Mint on multiple options in a single transaction
    /// @param options Array of Option contract addresses
    /// @param amounts Array of amounts to mint for each option (in collateral token decimals)
    /// @dev All options must have the same collateral token and factory
    /// @dev Caller must have already approved collateral to factory (both ERC20 and factory.approve)
    function batchMint(address[] calldata options, uint256[] calldata amounts) external {
        if (options.length != amounts.length) revert ArrayLengthMismatch();
        if (options.length == 0) return;

        uint256 totalAmount = 0;

        for (uint256 i = 0; i < options.length; i++) {
            if (options[i] == address(0)) revert ZeroAddress();
            if (amounts[i] == 0) revert ZeroAmount();

            totalAmount += amounts[i];

            // Mint with caller as the account (factory will pull from caller)
            IOption(options[i]).mint(msg.sender, amounts[i]);
        }

        emit BatchMintExecuted(msg.sender, options.length, totalAmount);
    }

    /// @notice Preview total collateral needed for a batch mint
    /// @param amounts Array of amounts to mint
    /// @return total Total collateral needed
    function previewBatchMint(uint256[] calldata amounts) external pure returns (uint256 total) {
        for (uint256 i = 0; i < amounts.length; i++) {
            total += amounts[i];
        }
    }
}
