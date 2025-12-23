// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

struct TokenData {
    address address_;
    string name;
    string symbol;
    uint8 decimals;
}

struct Balances {
    uint256 collateral;
    uint256 consideration;
    uint256 option;
    uint256 redemption;
}

struct OptionInfo {
    address option;
    address redemption;
    TokenData collateral;
    TokenData consideration;
    uint256 expiration;
    uint256 strike;
    bool isPut;
}

interface IOption {
    // ============ EVENTS ============

    event Mint(address longOption, address holder, uint256 amount);
    event Exercise(address longOption, address holder, uint256 amount);
    event ContractLocked();
    event ContractUnlocked();

    // ============ ERRORS ============

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

    // ============ STATE VARIABLES ============

    function redemption() external view returns (address);
    function fee() external view returns (uint64);

    // ============ INITIALIZATION ============

    function init(address redemption_, address owner, uint64 fee_) external;

    // ============ VIEW FUNCTIONS ============

    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function factory() external view returns (address);
    function collateral() external view returns (address);
    function consideration() external view returns (address);
    function expirationDate() external view returns (uint256);
    function strike() external view returns (uint256);
    function isPut() external view returns (bool);
    function balanceOf(address account) external view returns (uint256);
    function balancesOf(address account) external view returns (Balances memory);
    function details() external view returns (OptionInfo memory);

    // ============ STATE-CHANGING FUNCTIONS ============

    function mint(uint256 amount) external;
    function mint(address account, uint256 amount) external;
    function transferFrom(address from, address to, uint256 amount) external returns (bool success);
    function transfer(address to, uint256 amount) external returns (bool success);
    function exercise(uint256 amount) external;
    function exercise(address account, uint256 amount) external;
    function redeem(uint256 amount) external;
    function redeem(address account, uint256 amount) external;
    function lock() external;
    function unlock() external;
    function adjustFee(uint64 fee_) external;
    function claimFees() external;
}
