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
    uint256 coll;
}

struct OptionInfo {
    address option;
    address coll;
    TokenData collateral;
    TokenData consideration;
    uint256 expiration;
    uint256 strike;
    bool isPut;
    bool isEuro;
    address oracle;
}

interface IOption {
    event Mint(address longOption, address holder, uint256 amount);
    event Exercise(address longOption, address holder, uint256 amount);
    event Settled(uint256 price);
    event Claimed(address indexed holder, uint256 optionBurned, uint256 collateralOut);
    event ContractLocked();
    event ContractUnlocked();

    error ContractExpired();
    error ContractNotExpired();
    error InsufficientBalance();
    error InvalidValue();
    error InvalidAddress();
    error LockedContract();
    error NotEuropean();
    error NoOracle();
    error EuropeanExerciseDisabled();

    function coll() external view returns (address);
    function init(address coll_, address owner) external;

    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function factory() external view returns (address);
    function collateral() external view returns (address);
    function consideration() external view returns (address);
    function expirationDate() external view returns (uint256);
    function strike() external view returns (uint256);
    function isPut() external view returns (bool);
    function isEuro() external view returns (bool);
    function oracle() external view returns (address);
    function isSettled() external view returns (bool);
    function settlementPrice() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function balancesOf(address account) external view returns (Balances memory);
    function details() external view returns (OptionInfo memory);

    function mint(uint256 amount) external;
    function mint(address account, uint256 amount) external;
    function transferFrom(address from, address to, uint256 amount) external returns (bool success);
    function transfer(address to, uint256 amount) external returns (bool success);
    function exercise(uint256 amount) external;
    function exercise(address account, uint256 amount) external;
    function redeem(uint256 amount) external;
    function settle(bytes calldata hint) external;
    function claim(uint256 amount) external;
    function claimFor(address holder) external;
    function lock() external;
    function unlock() external;
}
