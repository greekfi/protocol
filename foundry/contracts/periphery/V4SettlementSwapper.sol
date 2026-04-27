// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { IPoolManager } from "v4-core/interfaces/IPoolManager.sol";
import { IUnlockCallback } from "v4-core/interfaces/callback/IUnlockCallback.sol";
import { IHooks } from "v4-core/interfaces/IHooks.sol";
import { PoolKey } from "v4-core/types/PoolKey.sol";
import { SwapParams } from "v4-core/types/PoolOperation.sol";
import { BalanceDelta } from "v4-core/types/BalanceDelta.sol";
import { Currency } from "v4-core/types/Currency.sol";

import { ISettlementSwapper } from "../interfaces/ISettlementSwapper.sol";

/// @title  V4SettlementSwapper
/// @author Greek.fi
/// @notice An {ISettlementSwapper} that routes through a single Uniswap v4 pool via the
///         flash-accounting API (`unlock` → `swap` → `sync/settle` → `take`). Stateless
///         between calls — pull in, swap out, deliver.
/// @dev    A deployed instance is bound to one `(PoolManager, fee, tickSpacing, hooks)`
///         tuple. The token ordering of the pool is derived per-call from the `tokenIn` /
///         `tokenOut` addresses. Deploy separate instances for separate fee tiers or
///         hook configurations.
contract V4SettlementSwapper is ISettlementSwapper, IUnlockCallback {
    using SafeERC20 for IERC20;

    /// @notice The Uniswap v4 PoolManager this swapper calls into.
    IPoolManager public immutable poolManager;
    /// @notice The `fee` field of the target PoolKey.
    uint24 public immutable fee;
    /// @notice The `tickSpacing` field of the target PoolKey.
    int24 public immutable tickSpacing;
    /// @notice The `hooks` field of the target PoolKey.
    address public immutable hooks;

    // TickMath MIN/MAX sqrt price bounds. Using min+1 / max-1 avoids the inclusive-bound reverts.
    uint160 internal constant MIN_SQRT_PRICE_PLUS_1 = 4295128740;
    uint160 internal constant MAX_SQRT_PRICE_MINUS_1 = 1461446703485210103287273052203988822378723970341;

    error OnlyPoolManager();
    error NegativeOutputDelta();

    constructor(IPoolManager poolManager_, uint24 fee_, int24 tickSpacing_, address hooks_) {
        poolManager = poolManager_;
        fee = fee_;
        tickSpacing = tickSpacing_;
        hooks = hooks_;
    }

    /// @inheritdoc ISettlementSwapper
    /// @dev `routeHint` is ignored — this swapper binds to a fixed pool at deployment.
    function swap(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minOut,
        address recipient,
        bytes calldata /* routeHint */
    ) external override returns (uint256 amountOut) {
        // Pull the input tokens from the caller (typically a Collateral contract).
        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);

        // Canonical token ordering (PoolKey requires currency0 < currency1).
        bool tokenInIsToken0 = tokenIn < tokenOut;
        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(tokenInIsToken0 ? tokenIn : tokenOut),
            currency1: Currency.wrap(tokenInIsToken0 ? tokenOut : tokenIn),
            fee: fee,
            tickSpacing: tickSpacing,
            hooks: IHooks(hooks)
        });

        bytes memory result = poolManager.unlock(abi.encode(key, tokenIn, tokenOut, amountIn, recipient, tokenInIsToken0));
        amountOut = abi.decode(result, (uint256));
        require(amountOut >= minOut, "minOut");
    }

    /// @notice v4 flash-accounting callback. All state changes happen here.
    function unlockCallback(bytes calldata raw) external override returns (bytes memory) {
        if (msg.sender != address(poolManager)) revert OnlyPoolManager();

        (PoolKey memory key, address tokenIn, address tokenOut, uint256 amountIn, address recipient, bool zeroForOne) =
            abi.decode(raw, (PoolKey, address, address, uint256, address, bool));

        // Exact-input swap: amountSpecified < 0.
        SwapParams memory sp = SwapParams({
            zeroForOne: zeroForOne,
            // forge-lint: disable-next-line(unsafe-typecast)
            amountSpecified: -int256(amountIn),
            sqrtPriceLimitX96: zeroForOne ? MIN_SQRT_PRICE_PLUS_1 : MAX_SQRT_PRICE_MINUS_1
        });
        BalanceDelta delta = poolManager.swap(key, sp, "");

        // Pay the input-side debt: sync → transfer → settle.
        poolManager.sync(Currency.wrap(tokenIn));
        IERC20(tokenIn).safeTransfer(address(poolManager), amountIn);
        poolManager.settle();

        // Extract the output-side positive delta and take it for the recipient.
        int128 outDelta128 = zeroForOne ? _amount1(delta) : _amount0(delta);
        if (outDelta128 < 0) revert NegativeOutputDelta();
        // forge-lint: disable-next-line(unsafe-typecast)
        uint256 amountOut = uint256(uint128(outDelta128));
        poolManager.take(Currency.wrap(tokenOut), recipient, amountOut);

        return abi.encode(amountOut);
    }

    function _amount0(BalanceDelta d) private pure returns (int128 a) {
        assembly { a := sar(128, d) }
    }

    function _amount1(BalanceDelta d) private pure returns (int128 a) {
        assembly { a := signextend(15, d) }
    }
}
