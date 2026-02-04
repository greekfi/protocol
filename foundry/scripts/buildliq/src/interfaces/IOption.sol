// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

interface IOption {
    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function factory() external view returns (address);
    function collateral() external view returns (address);
    function consideration() external view returns (address);
    function expirationDate() external view returns (uint256);
    function strike() external view returns (uint256);
    function isPut() external view returns (bool);
    function balanceOf(address account) external view returns (uint256);
    function mint(uint256 amount) external;
    function mint(address account, uint256 amount) external;
}
