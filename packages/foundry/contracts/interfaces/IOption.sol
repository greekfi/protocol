// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

struct OptionDetails {
    string optionName;
    string optionSymbol;
    string redName;
    string redSymbol;
    address collateral;
    address consideration;
    string collName;
    string consName;
    string collSymbol;
    string consSymbol;
    uint8 collDecimals;
    uint8 consDecimals;
    uint256 expirationDate;
    uint256 strike;
    bool isPut;
    uint256 totalSupply;
    bool locked;
    address redemption;
    address option;
}

interface IOption is IERC20 {
    event Mint(address longOption, address holder, uint256 amount);
    event Exercise(address longOption, address holder, uint256 amount);

    function redemption_() external view returns (address);

    function mint(uint256 amount) external;
    function mint(address account, uint256 amount) external;

    function exercise(uint256 amount) external;
    function exercise(address account, uint256 amount) external;

    function redeem(uint256 amount) external;
    function redeem(address account, uint256 amount) external;

    function setRedemption(address shortOptionAddress) external;

    function balancesOf(address account) external view
        returns (uint256 collBalance, uint256 consBalance, uint256 optionBalance, uint256 redemptionBalance);

    function details() external view returns (OptionDetails memory);
}