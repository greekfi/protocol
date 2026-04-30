// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @notice Parameters for {IFactory.createOption}.
/// @param collateral     Underlying collateral token (must not be blocklisted; must differ from consideration).
/// @param consideration  Quote / consideration token.
/// @param expirationDate Unix expiration timestamp (must be in the future).
/// @param strike         Strike price, 18-decimal fixed point (consideration per collateral; for puts
///                       this should be the inverted `1e36 / humanStrike`).
/// @param isPut          `true` for puts.
/// @param isEuro         `true` for European-style options (exercise barred pre-expiry; only the
///                       post-expiry window is exercisable). `false` for American.
/// @param windowSeconds  Length in seconds of the post-expiry exercise window. `0` means use the
///                       protocol default (8 hours = 28800). After `expirationDate + windowSeconds`,
///                       exercise reverts and short-side redemption opens.
struct CreateParams {
    address collateral;
    address consideration;
    uint40 expirationDate;
    uint96 strike;
    bool isPut;
    bool isEuro;
    uint40 windowSeconds;
}

/// @title  IFactory — option pair deployer + allowance hub
/// @author Greek.fi
/// @notice Deploys Option + Receipt pairs via EIP-1167 clones, serves as the single ERC20 approval
///         point for every option pair it creates, and holds an operator + auto-mint-redeem registry.
interface IFactory {
    /// @notice Emitted for every newly-created option.
    event OptionCreated(
        address indexed collateral,
        address indexed consideration,
        uint40 expirationDate,
        uint96 strike,
        bool isPut,
        bool isEuro,
        uint40 windowSeconds,
        address indexed option,
        address receipt
    );
    /// @notice Emitted on {blockToken} / {unblockToken}.
    event TokenBlocked(address token, bool blocked);
    /// @notice Emitted on {approveOperator}.
    event OperatorApproval(address indexed owner, address indexed operator, bool approved);
    /// @notice Emitted on {enableAutoMintBurn}.
    event AutoMintBurnUpdated(address indexed account, bool enabled);
    /// @notice Emitted on {approve} (factory-level allowance set).
    event Approval(address indexed token, address indexed owner, uint256 amount);

    /// @notice Attempted to create an option against a blocklisted collateral/consideration token.
    error BlocklistedToken();
    /// @notice Zero address supplied where a contract is required.
    error InvalidAddress();
    /// @notice Collateral and consideration were the same address.
    error InvalidTokens();
    /// @notice {transferFrom} called with `allowance < amount`.
    error InsufficientAllowance();

    /// @notice Receipt template clone.
    function RECEIPT_CLONE() external view returns (address);
    /// @notice Option template clone.
    function OPTION_CLONE() external view returns (address);
    /// @notice Default exercise window in seconds when `windowSeconds == 0` is supplied.
    function DEFAULT_EXERCISE_WINDOW() external view returns (uint40);
    /// @notice `true` if `token` is blocklisted for new option creation.
    function blocklist(address token) external view returns (bool);
    /// @notice `true` if `opt` is an Option produced by this factory.
    function options(address opt) external view returns (bool);
    /// @notice Factory-level allowance: how much of `token` the factory may pull from `owner`.
    function allowance(address token, address owner) external view returns (uint256);
    /// @notice Alias for {blocklist}.
    function isBlocked(address token) external view returns (bool);
    /// @notice `true` if `account` has opted into Option's auto-mint / auto-redeem transfer hooks.
    function autoMintBurn(address account) external view returns (bool);
    /// @notice `true` if `operator` has blanket authority over `owner`'s Option tokens.
    function approvedOperator(address owner, address operator) external view returns (bool);

    /// @notice Create a new Option + Collateral pair per the given parameters.
    function createOption(CreateParams memory params) external returns (address);
    /// @notice Backward-compatibility overload: defaults `windowSeconds` to the protocol default.
    function createOption(address collateral, address consideration, uint40 expirationDate, uint96 strike, bool isPut)
        external
        returns (address);
    /// @notice Batch form of {createOption}.
    function createOptions(CreateParams[] memory params) external returns (address[] memory);
    /// @notice Pull tokens via the factory-level allowance. Only callable by Collateral clones.
    function transferFrom(address from, address to, uint160 amount, address token) external returns (bool success);
    /// @notice Set the caller's factory-level allowance for `token`.
    function approve(address token, uint256 amount) external;
    /// @notice Owner-only: block `token` from new option creation.
    function blockToken(address token) external;
    /// @notice Owner-only: reverse of {blockToken}.
    function unblockToken(address token) external;
    /// @notice Opt-in / opt-out of Option's auto-mint-on-transfer / auto-redeem-on-receive behaviour.
    function enableAutoMintBurn(bool enabled) external;
    /// @notice Grant / revoke blanket operator authority over the caller's options.
    function approveOperator(address operator, bool approved) external;
}
