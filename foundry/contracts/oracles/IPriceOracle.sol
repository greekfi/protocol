// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @title  IPriceOracle — settlement oracle interface
/// @author Greek.fi
/// @notice Uniform interface exposed by every settlement oracle used by {Collateral}. Wraps Chainlink
///         aggregators, Uniswap v3 TWAPs, or any other source and exposes a single latched price
///         in the protocol's strike encoding (18-decimal fixed point, consideration-per-collateral).
/// @dev    Oracles are *write-once*: the first post-expiry `settle` latches `price()` forever, making
///         settlement deterministic even if the underlying source changes afterward. Idempotent —
///         re-settling is a safe no-op.
interface IPriceOracle {
    /// @notice Settlement target — must equal the paired option's expiration timestamp.
    function expiration() external view returns (uint256);

    /// @notice `true` iff {settle} has been called successfully and {price} is now available.
    function isSettled() external view returns (bool);

    /// @notice Latch the settlement price. Callable at or after {expiration} by anyone. Idempotent.
    /// @dev    `hint` is implementation-specific:
    ///           - `UniV3Oracle`: ignored (empty bytes).
    ///           - `ChainlinkOracle` (planned): `abi.encode(uint80 roundId)` — earliest round after expiry.
    /// @param  hint Implementation-specific settlement hint.
    /// @return The latched settlement price, 18-decimal fixed point (consideration per collateral).
    function settle(bytes calldata hint) external returns (uint256);

    /// @notice Read the latched settlement price. Reverts if {settle} has not yet run.
    /// @dev    Same encoding as {strike} on {Collateral}: 18-decimal fixed point, "consideration per collateral".
    function price() external view returns (uint256);
}
