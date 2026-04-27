// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { ISettlementSwapper } from "../interfaces/ISettlementSwapper.sol";

interface IUniversalRouter {
    function execute(bytes calldata commands, bytes[] calldata inputs, uint256 deadline) external payable;
}

/// @title  UniversalRouterSwapper
/// @author Greek.fi
/// @notice {ISettlementSwapper} backed by Uniswap's Universal Router. Routing is delegated
///         to whoever constructs the command payload (typically the off-chain Uniswap
///         auto-router service or any planning contract), so this swapper transparently
///         handles v2, v3, v4, and mixed-venue routes without on-chain pool selection.
///
/// @dev    `routeHint` must ABI-decode as `(bytes commands, bytes[] inputs)` — the two
///         arguments Universal Router's `execute` takes. The deadline is computed on-chain.
///         The command payload must produce at least `minOut` of `tokenOut` sent to
///         `recipient` (or to this swapper, in which case the residual is forwarded). The
///         swapper hands `amountIn` of `tokenIn` to the router before calling `execute`,
///         and encoders should use `payerIsUser=false` on swap commands so the router
///         pays from its own balance.
contract UniversalRouterSwapper is ISettlementSwapper {
    using SafeERC20 for IERC20;

    /// @notice The Universal Router instance this swapper calls into.
    IUniversalRouter public immutable universalRouter;

    constructor(IUniversalRouter universalRouter_) {
        universalRouter = universalRouter_;
    }

    /// @inheritdoc ISettlementSwapper
    function swap(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minOut,
        address recipient,
        bytes calldata routeHint
    ) external override returns (uint256 amountOut) {
        // Pull tokenIn from the calling Collateral contract.
        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);

        // Forward to the Universal Router. Caller-supplied payload encodes commands+inputs.
        IERC20(tokenIn).safeTransfer(address(universalRouter), amountIn);

        (bytes memory commands, bytes[] memory inputs) = abi.decode(routeHint, (bytes, bytes[]));

        uint256 recipientBefore = IERC20(tokenOut).balanceOf(recipient);
        uint256 swapperBefore = IERC20(tokenOut).balanceOf(address(this));

        universalRouter.execute(commands, inputs, block.timestamp);

        uint256 recipientAfter = IERC20(tokenOut).balanceOf(recipient);
        uint256 swapperAfter = IERC20(tokenOut).balanceOf(address(this));

        // Prefer direct delivery to recipient; if the route sent tokens here instead, sweep.
        uint256 delivered = recipientAfter - recipientBefore;
        uint256 stuck = swapperAfter - swapperBefore;
        if (stuck > 0) {
            IERC20(tokenOut).safeTransfer(recipient, stuck);
            delivered += stuck;
        }

        if (delivered < minOut) revert Slippage();
        amountOut = delivered;
    }

    error Slippage();
}
