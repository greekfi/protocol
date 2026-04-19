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
/// @param coll           Balance of the short-side Collateral ERC20.
struct Balances {
    uint256 collateral;
    uint256 consideration;
    uint256 option;
    uint256 coll;
}

/// @notice One-shot descriptor for a single option, returned by {IOption.details}.
/// @param option        Option contract address.
/// @param coll          Paired Collateral contract address.
/// @param collateral    Collateral token metadata.
/// @param consideration Consideration token metadata.
/// @param expiration    Unix expiration timestamp.
/// @param strike        18-decimal fixed-point strike price (consideration per collateral).
/// @param isPut         `true` for puts.
/// @param isEuro        `true` for European options.
/// @param oracle        Settlement oracle (`address(0)` in American non-settled mode).
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

/// @title  IOption — long-side option token interface
/// @author Greek.fi
/// @notice ERC20 with option-specific extensions: mint / exercise / redeem (pre-expiry),
///         settle / claim (post-expiry, settled modes). Transfers use auto-mint /
///         auto-redeem hooks when the sender / receiver has opted in on the factory.
interface IOption {
    /// @notice Emitted on {IOption.mint}.
    event Mint(address longOption, address holder, uint256 amount);
    /// @notice Emitted on {IOption.exercise} (American only).
    event Exercise(address longOption, address holder, uint256 amount);
    /// @notice Emitted once per option when the oracle settlement price is latched.
    event Settled(uint256 price);
    /// @notice Emitted on every post-expiry {IOption.claim} / {IOption.claimFor} payout.
    event Claimed(address indexed holder, uint256 optionBurned, uint256 collateralOut);
    /// @notice Emitted on {IOption.lock}.
    event ContractLocked();
    /// @notice Emitted on {IOption.unlock}.
    event ContractUnlocked();

    /// @notice Call that requires a live option was made after expiration.
    error ContractExpired();
    /// @notice Post-expiry-only call was made before expiration.
    error ContractNotExpired();
    /// @notice Account doesn't hold enough `Option` tokens for the operation.
    error InsufficientBalance();
    /// @notice Zero-amount mutation rejected.
    error InvalidValue();
    /// @notice Zero address supplied where a contract is required.
    error InvalidAddress();
    /// @notice Option has been paused by its owner.
    error LockedContract();
    /// @notice Reserved — kept for ABI compatibility.
    error NotEuropean();
    /// @notice Call requiring an oracle was made on an option without one.
    error NoOracle();
    /// @notice `exercise` was called on a European option.
    error EuropeanExerciseDisabled();

    /// @notice Paired short-side {Collateral} contract.
    function coll() external view returns (address);
    /// @notice One-time initialisation (factory-only for clones).
    function init(address coll_, address owner) external;

    /// @notice ERC20 name (rendered `OPT[E]-coll-cons-strike-YYYY-MM-DD`).
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
    /// @notice `true` if European-style (no pre-expiry exercise).
    function isEuro() external view returns (bool);
    /// @notice Settlement oracle (`address(0)` in American non-settled mode).
    function oracle() external view returns (address);
    /// @notice `true` once the oracle price has been latched.
    function isSettled() external view returns (bool);
    /// @notice Latched oracle price (0 until settled).
    function settlementPrice() external view returns (uint256);
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
    /// @notice Exercise `amount` options (American-only): pay consideration, receive collateral.
    function exercise(uint256 amount) external;
    /// @notice Exercise `amount` options on behalf of `account`.
    function exercise(address account, uint256 amount) external;
    /// @notice Burn matched Option + Collateral pair pre-expiry; return collateral.
    function redeem(uint256 amount) external;
    /// @notice Latch the oracle settlement price. Idempotent; callable post-expiry by anyone.
    function settle(bytes calldata hint) external;
    /// @notice Post-expiry ITM claim — burn `amount` options, receive the `(S-K)/S` residual.
    function claim(uint256 amount) external;
    /// @notice Claim on behalf of `holder` for their full balance.
    function claimFor(address holder) external;
    /// @notice Emergency pause (owner-only).
    function lock() external;
    /// @notice Reverse of {lock}.
    function unlock() external;
}
