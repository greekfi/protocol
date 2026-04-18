// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

struct CreateParams {
    address collateral;
    address consideration;
    uint40 expirationDate;
    uint96 strike;
    bool isPut;
    bool isEuro;
    address oracleSource;
    uint32 twapWindow;
}

interface IFactory {
    event OptionCreated(
        address indexed collateral,
        address indexed consideration,
        uint40 expirationDate,
        uint96 strike,
        bool isPut,
        bool isEuro,
        address oracle,
        address indexed option,
        address coll
    );
    event TokenBlocked(address token, bool blocked);
    event OperatorApproval(address indexed owner, address indexed operator, bool approved);
    event AutoMintRedeemUpdated(address indexed account, bool enabled);
    event Approval(address indexed token, address indexed owner, uint256 amount);

    error BlocklistedToken();
    error InvalidAddress();
    error InvalidTokens();
    error InsufficientAllowance();
    error EuropeanRequiresOracle();
    error UnsupportedOracleSource();

    function COLL_CLONE() external view returns (address);
    function OPTION_CLONE() external view returns (address);
    function blocklist(address token) external view returns (bool);
    function options(address opt) external view returns (bool);
    function allowance(address token, address owner) external view returns (uint256);
    function isBlocked(address token) external view returns (bool);
    function autoMintRedeem(address account) external view returns (bool);
    function approvedOperator(address owner, address operator) external view returns (bool);

    function createOption(CreateParams memory params) external returns (address);
    function createOption(address collateral, address consideration, uint40 expirationDate, uint96 strike, bool isPut)
        external
        returns (address);
    function createOptions(CreateParams[] memory params) external returns (address[] memory);
    function transferFrom(address from, address to, uint160 amount, address token) external returns (bool success);
    function approve(address token, uint256 amount) external;
    function blockToken(address token) external;
    function unblockToken(address token) external;
    function enableAutoMintRedeem(bool enabled) external;
    function approveOperator(address operator, bool approved) external;
}
