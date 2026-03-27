// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

/// @dev ABI-compatible copy of Bebop's JamOrder struct
struct JamOrder {
    address taker;
    address receiver;
    uint256 expiry;
    uint256 exclusivityDeadline;
    uint256 nonce;
    address executor;
    uint256 partnerInfo;
    address[] sellTokens;
    address[] buyTokens;
    uint256[] sellAmounts;
    uint256[] buyAmounts;
    bool usingPermit2;
}

/// @title IJamSettlement
/// @notice Minimal interface for Bebop's JamSettlement contract
interface IJamSettlement {
    function settleInternal(
        JamOrder calldata order,
        bytes calldata signature,
        uint256[] calldata filledAmounts,
        bytes memory hooksData
    ) external payable;

    function balanceManager() external view returns (address);
}
