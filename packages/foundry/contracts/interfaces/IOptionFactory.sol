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
    // ============ EVENTS ============

    event OptionCreated(
        address indexed collateral,
        address indexed consideration,
        uint40 expirationDate,
        uint96 strike,
        bool isPut,
        address indexed option,
        address redemption
    );

    event TokenBlocked(address token, bool blocked);
    event FeeUpdated(uint64 oldFee, uint64 newFee);
    event TemplateUpdated();

    // ============ ERRORS ============

    error BlocklistedToken();
    error InvalidAddress();
    error InvalidTokens();

    // ============ VIEW FUNCTIONS ============

    function redemptionClone() external view returns (address);
    function optionClone() external view returns (address);
    function fee() external view returns (uint64);
    function MAX_FEE() external view returns (uint256);
    function blocklist(address token) external view returns (bool);
    function allowance(address token, address owner) external view returns (uint256);
    function isBlocked(address token) external view returns (bool);

    // ============ STATE-CHANGING FUNCTIONS ============

    function createOption(address collateral, address consideration, uint40 expirationDate, uint96 strike, bool isPut)
        external
        returns (address);

    function createOptions(OptionParameter[] memory optionParams) external;
    function transferFrom(address from, address to, uint160 amount, address token) external returns (bool success);
    function approve(address token, uint256 amount) external;
    function blockToken(address token) external;
    function unblockToken(address token) external;
    function claimFees(address[] memory options, address[] memory tokens) external;
    function claimFees(address[] memory tokens) external;
    function optionsClaimFees(address[] memory options) external;
    function adjustFee(uint64 fee_) external;
}
