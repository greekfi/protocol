// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

struct OptionParameter {
    address collateral_;
    address consideration_;
    uint40 expiration;
    uint96 strike;
    bool isPut;
}

interface IOptionFactory {
    event OptionCreated(
        address collateral,
        address consideration,
        uint256 expirationDate,
        uint256 strike,
        bool isPut,
        address option,
        address redemption
    );

    event TokenBlocked(address token, bool blocked);

    error BlocklistedToken();
    error InvalidAddress();

    function redemptionClone() external view returns (address);
    function optionClone() external view returns (address);
    function fee() external view returns (uint64);
    function MAX_FEE() external view returns (uint256);
    function blocklist(address token) external view returns (bool);

    function createOption(
        address collateral,
        address consideration,
        uint40 expirationDate,
        uint96 strike,
        bool isPut
    ) external returns (address);

    function createOptions(OptionParameter[] memory optionParams) external;
    function transferFrom(address from, address to, uint160 amount, address token) external returns (bool success);
    function blockToken(address token) external;
    function unblockToken(address token) external;
    function isBlocked(address token) external view returns (bool);
}
