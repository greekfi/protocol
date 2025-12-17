// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

struct TokenData {
    address address_;
    string name;
    string symbol;
    uint8 decimals;
}

interface IRedemption {
    event Redeemed(address option, address token, address holder, uint256 amount);
    event ContractLocked();
    event ContractUnlocked();

    error ContractNotExpired();
    error ContractExpired();
    error InsufficientBalance();
    error InvalidValue();
    error InvalidAddress();
    error LockedContract();
    error FeeOnTransferNotSupported();
    error InsufficientCollateral();
    error InsufficientConsideration();
    error TokenBlocklisted();
    error ArithmeticOverflow();

    function fees() external view returns (uint256);
    function strike() external view returns (uint256);
    function collateral() external view returns (IERC20);
    function consideration() external view returns (IERC20);
    function _factory() external view returns (address);
    function fee() external view returns (uint64);
    function expirationDate() external view returns (uint40);
    function isPut() external view returns (bool);
    function locked() external view returns (bool);

    function init(
        address collateral_,
        address consideration_,
        uint40 expirationDate_,
        uint256 strike_,
        bool isPut_,
        address option_,
        address factory_,
        uint64 fee_
    ) external;

    function mint(address account, uint256 amount) external;
    function redeem(address account) external;
    function redeem(uint256 amount) external;
    function redeem(address account, uint256 amount) external;
    function _redeemPair(address account, uint256 amount) external;
    function redeemConsideration(uint256 amount) external;
    function redeemConsideration(address account, uint256 amount) external;
    function exercise(address account, uint256 amount, address caller) external;
    function sweep(address holder) external;
    function sweep(address[] calldata holders) external;
    function claimFees() external;
    function lock() external;
    function unlock() external;
    function toConsideration(uint256 amount) external view returns (uint256);
    function toCollateral(uint256 consAmount) external view returns (uint256);
    function toFee(uint256 amount) external view returns (uint256);
    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function decimals() external view returns (uint8);
    function collateralData() external view returns (TokenData memory);
    function considerationData() external view returns (TokenData memory);
    function option() external view returns (address);
}
