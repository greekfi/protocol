// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @notice Minimal ERC20 metadata bundle returned by {IOption.balancesOf} and {IOption.details}.
/// @param address_ Token contract address.
/// @param name     Token name.
/// @param symbol   Token symbol.
/// @param decimals Token decimals.
struct TokenData {
    address address_;
    string name;
    string symbol;
    uint8 decimals;
}

/// @notice All balances relevant to a single option pair for an address (used by dashboards / scripts).
/// @param collateral     Balance of the underlying collateral token.
/// @param consideration  Balance of the consideration token.
/// @param option         Balance of the long-side Option ERC20.
/// @param receipt        Balance of the short-side Receipt ERC20.
struct Balances {
    uint256 collateral;
    uint256 consideration;
    uint256 option;
    uint256 receipt;
}

/// @notice One-shot descriptor for a single option, returned by {IOption.details}.
/// @param option            Option contract address.
/// @param receipt           Paired Receipt contract address.
/// @param collateral        Collateral token metadata.
/// @param consideration     Consideration token metadata.
/// @param expiration        Unix expiration timestamp.
/// @param strike            18-decimal fixed-point strike price (consideration per collateral).
/// @param isPut             `true` for puts.
/// @param isEuro            `true` for European options (no pre-expiry exercise).
/// @param exerciseDeadline  Unix timestamp at which the post-expiry exercise window closes.
struct OptionInfo {
    address option;
    address receipt;
    TokenData collateral;
    TokenData consideration;
    uint256 expiration;
    uint256 strike;
    bool isPut;
    bool isEuro;
    uint40 exerciseDeadline;
}

/// @title  IOption — long-side option token interface
/// @author Greek.fi
/// @notice ERC20 with option-specific extensions: mint, exercise, pair-redeem. Exercise is allowed
///         pre-expiry and during a post-expiry window (`exerciseDeadline = expirationDate + windowSeconds`),
///         after which only short-side redemption is permitted.
interface IOption {
    /// @notice Emitted on {IOption.mint}.
    event Mint(address longOption, address holder, uint256 amount);
    /// @notice Emitted on any {IOption.exercise} overload.
    event Exercise(address longOption, address holder, uint256 amount);

    /// @notice Call that requires a live option was made after expiration.
    error ContractExpired();
    /// @notice Account doesn't hold enough `Option` tokens for the operation.
    error InsufficientBalance();
    /// @notice Zero-amount mutation rejected.
    error InvalidValue();
    /// @notice Zero address supplied where a contract is required.
    error InvalidAddress();
    /// @notice Exercise was attempted after `exerciseDeadline`.
    error ExerciseWindowClosed();
    /// @notice Pre-expiry exercise was attempted on a European option.
    error EuropeanExerciseDisabled();

    /// @notice Paired short-side {Receipt} contract.
    function receipt() external view returns (address);
    /// @notice One-time initialisation (factory-only for clones).
    function init(address receipt_, address owner) external;

    /// @notice ERC20 name (rendered `OPT-coll-cons-strike-YYYY-MM-DD`).
    function name() external view returns (string memory);
    /// @notice ERC20 symbol (matches `name`).
    function symbol() external view returns (string memory);
    /// @notice Address of the {Factory} that created this option.
    function factory() external view returns (address);
    /// @notice Underlying collateral token.
    function collateral() external view returns (address);
    /// @notice Consideration / quote token.
    function consideration() external view returns (address);
    /// @notice Unix expiration timestamp.
    function expirationDate() external view returns (uint256);
    /// @notice Strike price (18-decimal fixed point; inverted for puts).
    function strike() external view returns (uint256);
    /// @notice `true` if this is a put.
    function isPut() external view returns (bool);
    /// @notice `true` if European-style (exercise only allowed in the post-expiry window).
    function isEuro() external view returns (bool);
    /// @notice Unix timestamp at which the post-expiry exercise window closes.
    function exerciseDeadline() external view returns (uint40);
    /// @notice ERC20 balance.
    function balanceOf(address account) external view returns (uint256);
    /// @notice All four balances that matter for this option.
    function balancesOf(address account) external view returns (Balances memory);
    /// @notice Full option descriptor.
    function details() external view returns (OptionInfo memory);

    /// @notice Mint `amount` options to the caller.
    function mint(uint256 amount) external;
    /// @notice Mint `amount` options to `account`.
    function mint(address account, uint256 amount) external;
    /// @notice ERC20 transferFrom override — runs auto-mint + auto-redeem hooks; reverts post-expiry.
    function transferFrom(address from, address to, uint256 amount) external returns (bool success);
    /// @notice ERC20 transfer override — runs auto-mint + auto-redeem hooks; reverts post-expiry.
    function transfer(address to, uint256 amount) external returns (bool success);
    /// @notice Exercise `amount` options as the caller: pay consideration, receive collateral.
    ///         Allowed pre-expiry and within the post-expiry exercise window.
    function exercise(uint256 amount) external;
    /// @notice Authorised on-behalf exercise: burn `holder`'s options, pull consideration from
    ///         `msg.sender`, send collateral to `msg.sender`. Caller must be `holder` or have been
    ///         authorised via `factory.allowExercise` / `factory.approveOperator`.
    function exercise(address holder, uint256 amount) external;
    /// @notice Batch variant of {exercise}; caller receives all collateral, pays all consideration.
    function exercise(address[] calldata holders, uint256[] calldata amounts) external;
    /// @notice Burn matched Option + Receipt pair; return collateral. Allowed pre-deadline only.
    function burn(uint256 amount) external;
}
