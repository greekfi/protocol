// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

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

    // IPermit2 public constant PERMIT2 = IPermit2(0x000000000022D473030F116dDEE9F6B43aC78BA3);
    // uint256 public expirationDate;
    // uint256 public strike;
    // uint256 public constant STRIKE_DECIMALS = 10 ** 18;
    // // The strike price includes the ratio of the consideration to the collateral
    // // and the decimal difference between the consideration and collateral along
    // // with the strike decimals of 18.
    // bool public isPut;
    // IERC20 public collateral;
    // IERC20 public consideration;
    // IERC20Metadata cons;
    // IERC20Metadata coll;
    // uint8 consDecimals;
    // uint8 collDecimals;
    // bool public initialized = false;
    // string private _tokenName;
    // string private _tokenSymbol;
    // bool public locked = false;

    function collateral() external view returns (IERC20);
    function consideration() external view returns (IERC20);

    function expirationDate() external view returns (uint256);
    function strike() external view returns (uint256);
    function isPut() external view returns (bool);
    function redemption_() external view returns (address);

    function mint(uint256 amount) external;
    function mint(address account, uint256 amount) external;

    function exercise(uint256 amount) external;
    function exercise(address account, uint256 amount) external;

    function redeem(uint256 amount) external;
    function redeem(address account, uint256 amount) external;

    function setRedemption(address shortOptionAddress) external;

    function balancesOf(address account)
        external
        view
        returns (uint256 collBalance, uint256 consBalance, uint256 optionBalance, uint256 redemptionBalance);

    function details() external view returns (OptionDetails memory);
}
