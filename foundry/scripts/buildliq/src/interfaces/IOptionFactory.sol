// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

interface IOptionFactory {
    function fee() external view returns (uint64);
    function allowance(address token, address owner) external view returns (uint256);
    function approve(address token, uint256 amount) external;
    function transferFrom(address from, address to, uint160 amount, address token) external returns (bool success);
}
