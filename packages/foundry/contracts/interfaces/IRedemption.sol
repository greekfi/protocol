// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IRedemption is IERC20 {
    event Redeemed(address option, address token, address holder, uint256 amount);

    function option() external view returns (address);
    function accounts(uint256 index) external view returns (address);

    function setOption(address option_) external;

    function mint(address account, uint256 amount) external;

    function redeem(address account) external;
    function redeem(uint256 amount) external;
    function redeem(address account, uint256 amount) external;

    function _redeemPair(address account, uint256 amount) external;

    function redeemConsideration(uint256 amount) external;
    function redeemConsideration(address account, uint256 amount) external;

    function exercise(address account, uint256 amount, address caller) external;

    function sweep(address holder) external;
    function sweep() external;
}