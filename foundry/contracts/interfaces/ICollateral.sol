// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {TokenData} from "./IOption.sol";

/// @title  ICollateral — short-side token interface
/// @author Greek.fi
/// @notice ERC20 extension for the short-side position: holds underlying collateral, receives
///         consideration on exercise, and handles post-expiry settlement + redemption math.
interface ICollateral {
    /// @notice Emitted whenever collateral or consideration is returned to a user.
    event Redeemed(address option, address token, address holder, uint256 amount);
    /// @notice Emitted once per option when the oracle settlement price is latched.
    event Settled(uint256 price);

    /// @notice Pre-expiry-only path was called after expiration.
    error ContractNotExpired();
    /// @notice Post-expiry-only path was called before expiration.
    error ContractExpired();
    /// @notice Account lacks enough Collateral tokens for this operation.
    error InsufficientBalance();
    /// @notice Zero-amount (or derived-zero) mutation rejected.
    error InvalidValue();
    /// @notice Zero address supplied where a contract is required.
    error InvalidAddress();
    /// @notice Option has been paused by its owner.
    error LockedContract();
    /// @notice Fee-on-transfer token detected (transfer debit ≠ transfer credit).
    error FeeOnTransferNotSupported();
    /// @notice Contract holds less collateral than `amount`.
    error InsufficientCollateral();
    /// @notice Caller holds less consideration than `toConsideration(amount)`.
    error InsufficientConsideration();
    /// @notice Casting `amount` to `uint160` would overflow the Permit2 cap.
    error ArithmeticOverflow();
    /// @notice Call requiring an oracle was made on an option without one.
    error NoOracle();
    /// @notice Read relies on a settlement price that hasn't been latched yet.
    error NotSettled();
    /// @notice Settled-only path invoked in non-settled mode.
    error SettledOnly();
    /// @notice Non-settled-only path invoked in settled mode.
    error NonSettledOnly();

    /// @notice Strike price (18-decimal fixed point, consideration per collateral; inverted for puts).
    function strike() external view returns (uint256);
    /// @notice Underlying collateral token.
    function collateral() external view returns (IERC20);
    /// @notice Consideration / quote token.
    function consideration() external view returns (IERC20);
    /// @notice Unix expiration timestamp (uint40).
    function expirationDate() external view returns (uint40);
    /// @notice `true` if this is a put.
    function isPut() external view returns (bool);
    /// @notice `true` if European-style (no pre-expiry exercise).
    function isEuro() external view returns (bool);
    /// @notice Owner-controlled emergency pause flag.
    function locked() external view returns (bool);
    /// @notice Cached `consideration.decimals()`.
    function consDecimals() external view returns (uint8);
    /// @notice Cached `collateral.decimals()`.
    function collDecimals() external view returns (uint8);
    /// @notice Decimal basis of the strike (always 18).
    function STRIKE_DECIMALS() external view returns (uint8);
    /// @notice Settlement oracle (`address(0)` in American non-settled mode).
    function oracle() external view returns (address);
    /// @notice Latched oracle price (0 until first post-expiry {settle}).
    function settlementPrice() external view returns (uint256);
    /// @notice `true` once the option-holder reserve has been initialised.
    function reserveInitialized() external view returns (bool);
    /// @notice Collateral set aside for option-holder ITM claims; decremented on each claim.
    function optionReserveRemaining() external view returns (uint256);

    /// @notice One-time initialisation (factory-only for clones).
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

    /// @notice ERC20 name (rendered `CLL[E]-coll-cons-strike-YYYY-MM-DD`).
    function name() external view returns (string memory);
    /// @notice ERC20 symbol (matches `name`).
    function symbol() external view returns (string memory);
    /// @notice Matches `collateral().decimals()`.
    function decimals() external view returns (uint8);
    /// @notice Metadata bundle for the collateral token.
    function collateralData() external view returns (TokenData memory);
    /// @notice Metadata bundle for the consideration token.
    function considerationData() external view returns (TokenData memory);
    /// @notice Paired {IOption} contract (also the Ownable owner).
    function option() external view returns (address);
    /// @notice Factory that created this pair.
    function factory() external view returns (address);
    /// @notice Floor-rounded conversion used for payouts.
    function toConsideration(uint256 amount) external view returns (uint256);
    /// @notice Ceiling-rounded conversion used when collecting consideration (exercise).
    function toNeededConsideration(uint256 amount) external view returns (uint256);
    /// @notice Inverse of {toConsideration} — how much collateral a given consideration amount is worth.
    function toCollateral(uint256 consAmount) external view returns (uint256);

    /// @notice Mint (Option-only). Pulls collateral from `account` via the factory.
    function mint(address account, uint256 amount) external;
    /// @notice Redeem `amount` of caller's Collateral post-expiry.
    function redeem(uint256 amount) external;
    /// @notice Redeem `amount` of `account`'s Collateral post-expiry (anyone may call — sweeps).
    function redeem(address account, uint256 amount) external;
    /// @notice Pair-redeem helper called by the paired {IOption} on pre-expiry close-out.
    function _redeemPair(address account, uint256 amount) external;
    /// @notice Convert Collateral directly to consideration at the strike rate (American only).
    function redeemConsideration(uint256 amount) external;
    /// @notice Exercise path invoked by {IOption}: `caller` pays consideration; `account` receives collateral.
    function exercise(address account, uint256 amount, address caller) external;
    /// @notice Latch the oracle settlement price. Idempotent; callable post-expiry.
    function settle(bytes calldata hint) external;
    /// @notice Option-holder ITM payout helper (Option-only).
    function _claimForOption(address holder, uint256 amount) external returns (uint256);
    /// @notice Sweep a single holder's balance post-expiry.
    function sweep(address holder) external;
    /// @notice Batch sweep.
    function sweep(address[] calldata holders) external;
    /// @notice Emergency pause (owner-only).
    function lock() external;
    /// @notice Reverse of {lock}.
    function unlock() external;
}
