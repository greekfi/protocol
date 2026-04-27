// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @title  ISettlementSwapper
/// @author Greek.fi
/// @notice Narrow, DEX-agnostic interface a {Collateral} contract calls to convert its
///         residual collateral into consideration at post-expiry cash settlement. Each
///         swapper implementation wraps one venue (Uniswap v4 flash accounting,
///         Uniswap Universal Router, 1inch AggregationRouter, 0x, an RFQ feed, etc.).
///         The protocol does not privilege any implementation — the caller of
///         `Collateral.convertResidualToConsideration` picks one and is responsible for
///         the `minOut` slippage guard.
interface ISettlementSwapper {
    /// @notice Pull `amountIn` of `tokenIn` from `msg.sender` and deliver at least
    ///         `minOut` of `tokenOut` to `recipient`.
    /// @dev    The caller MUST have approved `amountIn` of `tokenIn` to this swapper
    ///         before invoking. Implementations revert if they cannot meet `minOut`.
    ///
    ///         `routeHint` is opaque venue-specific calldata. For swappers that bind to
    ///         a fixed pool at deployment (e.g. the canonical `V4SettlementSwapper`) it
    ///         is ignored. For aggregator-backed swappers (e.g. `UniversalRouterSwapper`,
    ///         `ZeroExSwapper`) it carries the off-chain-computed route calldata — this
    ///         is how "pick the best pool right now" is delegated to the caller.
    /// @return amountOut The amount of `tokenOut` actually delivered (≥ `minOut`).
    function swap(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minOut,
        address recipient,
        bytes calldata routeHint
    ) external returns (uint256 amountOut);
}
