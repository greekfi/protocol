// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { BaseHook } from "@openzeppelin/uniswap-hooks/src/base/BaseHook.sol";

import { Hooks } from "@uniswap/v4-core/src/libraries/Hooks.sol";
import { IPoolManager } from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import { SwapParams, ModifyLiquidityParams } from "@uniswap/v4-core/src/types/PoolOperation.sol";
import { PoolKey } from "@uniswap/v4-core/src/types/PoolKey.sol";
import { PoolIdLibrary } from "@uniswap/v4-core/src/types/PoolId.sol";
import { BeforeSwapDelta, toBeforeSwapDelta } from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";
import { Currency } from "@uniswap/v4-core/src/types/Currency.sol";
import { SafeCast } from "@uniswap/v4-core/src/libraries/SafeCast.sol";
import { IHooks } from "@uniswap/v4-core/src/interfaces/IHooks.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";

import { IOption } from "./interfaces/IOption.sol";
import { IPermit2 } from "./interfaces/IPermit2.sol";

using SafeERC20 for IERC20;

interface IHookVault {
    function price(address option, uint256 amount, bool isBuy)
        external
        view
        returns (uint256 outputAmount, uint256 unitPrice);
    function sellOptions(address option, address to, uint256 amount) external;
    function recordBuyback(address option, uint256 amount) external;
    function swap(address cashToken, bool cashToCollateral, uint256 amount) external returns (uint256 amountOut);
}

uint160 constant SQRT_PRICE_X96 = 1 << 96;
int24 constant TICK_SPACING = type(int16).max;

struct PoolInfo {
    address optionToken;
    address cashToken;
    bool optionIsOne;
    IHookVault vault;
}

/// @title OpHook
/// @notice Uniswap v4 hook that swaps Option tokens from HookVaults.
///         No pricing logic — delegates everything to the vault/propAMM style.
///         Sell: vault auto-mints options via transferFrom. Buy: auto-redeem + v3 swap.
contract OpHook is BaseHook, Ownable, ReentrancyGuard, Pausable {
    using PoolIdLibrary for PoolKey;
    using SafeERC20 for IERC20;

    // ============ Events ============

    event PoolCreated(address indexed optionToken, address indexed cashToken, address indexed vault, bytes32 poolId);
    event PoolDelisted(bytes32 indexed poolId);
    event Swap(address indexed sender, address indexed recipient, address indexed option, int256 amount, uint256 price);

    // ============ State ============

    IPermit2 public immutable PERMIT2;
    address public pm;

    mapping(bytes32 => PoolInfo) public pools;
    mapping(address => mapping(address => PoolInfo)) public optionCashPool;

    // ============ Constructor ============

    constructor(address _poolManager, address permit2) BaseHook(IPoolManager(_poolManager)) Ownable(msg.sender) {
        PERMIT2 = IPermit2(permit2);
        pm = _poolManager;
    }

    // ============ Hook Permissions ============

    function getHookPermissions() public pure override returns (Hooks.Permissions memory permissions) {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: false,
            beforeAddLiquidity: true,
            afterAddLiquidity: false,
            beforeRemoveLiquidity: false,
            afterRemoveLiquidity: false,
            beforeSwap: true,
            afterSwap: false,
            beforeDonate: true,
            afterDonate: false,
            beforeSwapReturnDelta: true,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    // ============ Pool Management ============

    function initPool(address optionToken, address cashToken, uint24 fee, address vault_)
        public
        onlyOwner
        returns (PoolKey memory)
    {
        bool optionIsOne = cashToken < optionToken;
        address token0 = optionIsOne ? cashToken : optionToken;
        address token1 = optionIsOne ? optionToken : cashToken;

        PoolKey memory poolKey = PoolKey({
            currency0: Currency.wrap(token0),
            currency1: Currency.wrap(token1),
            fee: fee,
            tickSpacing: TICK_SPACING,
            hooks: IHooks(address(this))
        });
        poolManager.initialize(poolKey, SQRT_PRICE_X96);

        PoolInfo memory info = PoolInfo({
            optionToken: optionToken, cashToken: cashToken, optionIsOne: optionIsOne, vault: IHookVault(vault_)
        });

        bytes32 poolId = _toId(poolKey);
        pools[poolId] = info;
        optionCashPool[optionToken][cashToken] = info;

        emit PoolCreated(optionToken, cashToken, vault_, poolId);
        return poolKey;
    }

    function delistPool(bytes32 poolId) external onlyOwner {
        PoolInfo memory info = pools[poolId];
        delete optionCashPool[info.optionToken][info.cashToken];
        delete pools[poolId];
        emit PoolDelisted(poolId);
    }

    // ============ Direct Swap (bypass Uni v4) ============

    function swapForOption(
        address optionToken,
        address cashToken_,
        uint256 cashAmount,
        uint256 minOptionsOut,
        address to
    ) public nonReentrant {
        require(to != address(0), "bad to");

        PoolInfo memory pool = optionCashPool[optionToken][cashToken_];
        require(address(pool.vault) != address(0), "Pool not found");

        (uint256 optionsOut, uint256 unitPrice) = pool.vault.price(optionToken, cashAmount, true);
        require(optionsOut >= minOptionsOut, "Slippage exceeded");

        // Pull cash from buyer to vault
        IERC20(cashToken_).safeTransferFrom(msg.sender, address(pool.vault), cashAmount);

        // Vault sells options via auto-mint
        pool.vault.sellOptions(optionToken, to, optionsOut);

        // Vault swaps received cash → collateral
        pool.vault.swap(pool.cashToken, true, 0);

        emit Swap(msg.sender, to, optionToken, int256(cashAmount), unitPrice);
    }

    function swapForOption(address optionToken, address cashToken_, uint256 cashAmount, uint256 minOptionsOut)
        external
    {
        swapForOption(optionToken, cashToken_, cashAmount, minOptionsOut, msg.sender);
    }

    // ============ Uni v4 Hook: Before Swap ============

    function _beforeSwap(address, PoolKey calldata key, SwapParams calldata params, bytes calldata hookData)
        internal
        override
        returns (bytes4 selector, BeforeSwapDelta delta, uint24 zeroReturn)
    {
        require(params.amountSpecified < 0, "amountSpecified must be negative");
        zeroReturn = 0;
        selector = BaseHook.beforeSwap.selector;

        PoolInfo memory pool = pools[_toId(key)];
        require(address(pool.vault) != address(0), "Unknown pool");

        bool cashForOption = pool.optionIsOne ? params.zeroForOne : !params.zeroForOne;
        Currency cashCurrency = pool.optionIsOne ? key.currency0 : key.currency1;
        Currency optionCurrency = pool.optionIsOne ? key.currency1 : key.currency0;

        IOption option = IOption(pool.optionToken);
        require(option.expirationDate() > block.timestamp, "Option expired");

        uint256 inputAmount = uint256(-params.amountSpecified);

        if (cashForOption) {
            // User buys options with cash
            (uint256 optionsOut,) = pool.vault.price(pool.optionToken, inputAmount, true);

            if (hookData.length >= 32) {
                uint256 minOut = abi.decode(hookData, (uint256));
                require(optionsOut >= minOut, "Slippage exceeded");
            }

            // Cash → vault
            poolManager.take(cashCurrency, address(pool.vault), inputAmount);

            // Vault auto-mints and delivers options to PM
            poolManager.sync(optionCurrency);
            pool.vault.sellOptions(pool.optionToken, pm, optionsOut);
            poolManager.settle();

            // Vault swaps cash → collateral
            pool.vault.swap(pool.cashToken, true, 0);

            delta = toBeforeSwapDelta(_to128(inputAmount), -_to128(optionsOut));
        } else {
            // User sells options for cash (buyback)
            (uint256 cashOut,) = pool.vault.price(pool.optionToken, inputAmount, false);

            // Options → vault (auto-redeem fires, returns collateral)
            poolManager.take(optionCurrency, address(pool.vault), inputAmount);

            // Record buyback for bookkeeping + inventory
            pool.vault.recordBuyback(pool.optionToken, inputAmount);

            // Vault swaps collateral → cash
            pool.vault.swap(pool.cashToken, false, cashOut);

            // Hook pulls cash from vault to PM
            poolManager.sync(cashCurrency);
            IERC20(pool.cashToken).safeTransferFrom(address(pool.vault), pm, cashOut);
            poolManager.settle();

            delta = toBeforeSwapDelta(_to128(inputAmount), -_to128(cashOut));
        }
    }

    // ============ Liquidity/Donate Guards ============

    function _beforeAddLiquidity(address, PoolKey calldata, ModifyLiquidityParams calldata, bytes calldata)
        internal
        pure
        override
        returns (bytes4)
    {
        revert("Cannot Add Liquidity to This Pool");
    }

    function _beforeDonate(address, PoolKey calldata, uint256, uint256, bytes calldata)
        internal
        pure
        override
        returns (bytes4)
    {
        revert("Cannot Donate to This Pool");
    }

    // ============ Internal ============

    function _toId(PoolKey memory k) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(Currency.unwrap(k.currency0), Currency.unwrap(k.currency1), k.fee, k.tickSpacing, k.hooks)
        );
    }

    function _to128(uint256 x) internal pure returns (int128 y) {
        return SafeCast.toInt128(int256(x));
    }
}
