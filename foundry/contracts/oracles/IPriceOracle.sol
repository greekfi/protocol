// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @title IPriceOracle
/// @notice Uniform oracle interface for European option settlement.
///         Implementations wrap Chainlink aggregators, Uniswap v3 TWAPs, or any other source
///         and expose a latched settlement price in 18-decimal fixed point.
interface IPriceOracle {
    /// @notice Settlement target timestamp (option expiration).
    function expiration() external view returns (uint256);

    /// @notice Whether `settle()` has been called and the price is locked in.
    function isSettled() external view returns (bool);

    /// @notice Latches the settlement price. Callable after expiration.
    ///         Idempotent: re-calling after settlement is a no-op.
    ///         `hint` is implementation-specific:
    ///           - UniV3Oracle: ignored (empty bytes).
    ///           - ChainlinkOracle: `abi.encode(uint80 roundId)` — earliest round after expiry.
    /// @return The settlement price, in 18-decimal fixed point, consideration per collateral.
    function settle(bytes calldata hint) external returns (uint256);

    /// @notice The latched settlement price. Reverts if not yet settled.
    /// @dev 18-decimal fixed point, "consideration per collateral" — matches the strike encoding.
    function price() external view returns (uint256);
}
