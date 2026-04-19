// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { TokenData } from "./IOption.sol";

interface ICollateral {
    event Redeemed(address option, address token, address holder, uint256 amount);
    event Settled(uint256 price);

    error ContractNotExpired();
    error ContractExpired();
    error InsufficientBalance();
    error InvalidValue();
    error InvalidAddress();
    error LockedContract();
    error FeeOnTransferNotSupported();
    error InsufficientCollateral();
    error InsufficientConsideration();
    error ArithmeticOverflow();
    error NoOracle();
    error NotSettled();
    error SettledOnly();
    error NonSettledOnly();

    function strike() external view returns (uint256);
    function collateral() external view returns (IERC20);
    function consideration() external view returns (IERC20);
    function expirationDate() external view returns (uint40);
    function isPut() external view returns (bool);
    function isEuro() external view returns (bool);
    function locked() external view returns (bool);
    function consDecimals() external view returns (uint8);
    function collDecimals() external view returns (uint8);
    function STRIKE_DECIMALS() external view returns (uint8);
    function oracle() external view returns (address);
    function settlementPrice() external view returns (uint256);
    function reserveInitialized() external view returns (bool);
    function optionReserveRemaining() external view returns (uint256);

    function init(
        address collateral_,
        address consideration_,
        uint40 expirationDate_,
        uint256 strike_,
        bool isPut_,
        bool isEuro_,
        address oracle_,
        address option_,
        address factory_
    ) external;

    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function decimals() external view returns (uint8);
    function collateralData() external view returns (TokenData memory);
    function considerationData() external view returns (TokenData memory);
    function option() external view returns (address);
    function factory() external view returns (address);
    function toConsideration(uint256 amount) external view returns (uint256);
    function toNeededConsideration(uint256 amount) external view returns (uint256);
    function toCollateral(uint256 consAmount) external view returns (uint256);

    function mint(address account, uint256 amount) external;
    function redeem(uint256 amount) external;
    function redeem(address account, uint256 amount) external;
    function _redeemPair(address account, uint256 amount) external;
    function redeemConsideration(uint256 amount) external;
    function exercise(address account, uint256 amount, address caller) external;
    function settle(bytes calldata hint) external;
    function _claimForOption(address holder, uint256 amount) external returns (uint256);
    function sweep(address holder) external;
    function sweep(address[] calldata holders) external;
    function lock() external;
    function unlock() external;
}
