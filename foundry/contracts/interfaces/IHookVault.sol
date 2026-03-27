// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @title IHookVault
/// @notice Interface for vaults used by OpHook for option swaps.
interface IHookVault {
    function getQuote(address option, uint256 amount, bool cashForOption)
        external
        view
        returns (uint256 outputAmount, uint256 unitPrice);

    function mintAndDeliver(address option, uint256 amount, address buyer) external returns (uint256 delivered);

    function pairRedeem(address option, uint256 amount) external;

    function transferCash(address token, uint256 amount, address to) external;
}
