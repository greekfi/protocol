// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { Test } from "forge-std/Test.sol";
import { console } from "forge-std/console.sol";
import { OpHook } from "../contracts/OpHook.sol";
import { Option, Redemption } from "../contracts/Option.sol";
import { YieldVault } from "../contracts/YieldVault.sol";
import { BlackScholes } from "../contracts/BlackScholes.sol";
import { HookMiner } from "@uniswap/v4-periphery/src/utils/HookMiner.sol";
import { IPoolManager } from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";

import { Hooks } from "@uniswap/v4-core/src/libraries/Hooks.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IWETH9 } from "@uniswap/v4-periphery/src/interfaces/external/IWETH9.sol";
import { UniversalRouter } from "@uniswap/universal-router/contracts/UniversalRouter.sol";
import { IV4Router } from "@uniswap/v4-periphery/src/interfaces/IV4Router.sol";
import { Actions } from "@uniswap/v4-periphery/src/libraries/Actions.sol";

import { CurrencySettler } from "@uniswap/v4-core/test/utils/CurrencySettler.sol";
import { SwapParams, PoolKey } from "@uniswap/v4-core/src/types/PoolOperation.sol";
import { BalanceDelta } from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import { Currency } from "@uniswap/v4-core/src/types/Currency.sol";
import { TickMath } from "@uniswap/v4-core/src/libraries/TickMath.sol";

import { IPermit2 } from "../contracts/interfaces/IPermit2.sol";
import { SafeCallback } from "./SafeCallback.sol";
import { NonzeroDeltaCount } from "@uniswap/v4-core/src/libraries/NonzeroDeltaCount.sol";
import { ConstantsMainnet } from "../contracts/ConstantsMainnet.sol";
import { ConstantsBase } from "../contracts/ConstantsBase.sol";

import { IOption } from "../contracts/interfaces/IOption.sol";
import { OptionFactory } from "../contracts/OptionFactory.sol";

contract SwapCallback is SafeCallback {
    OpHook public opHook;
    PoolKey public poolKey;
    bool public zeroForOne;

    using CurrencySettler for Currency;

    constructor(IPoolManager _poolManager, OpHook _opHook, PoolKey memory _poolKey, bool _zeroForOne)
        SafeCallback(_poolManager)
    {
        poolKey = _poolKey;
        opHook = _opHook;
        zeroForOne = _zeroForOne;
    }

    function _unlockCallback(bytes calldata data) internal override returns (bytes memory returnData) {
        (, uint256 amountIn) = abi.decode(data, (address, uint256));

        uint160 sqrtPriceLimit = zeroForOne ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1;

        SwapParams memory params = SwapParams({
            zeroForOne: zeroForOne, amountSpecified: -int128(int256(amountIn)), sqrtPriceLimitX96: sqrtPriceLimit
        });

        BalanceDelta delta = poolManager.swap(poolKey, params, bytes(""));

        if (zeroForOne) {
            poolKey.currency0.settle(poolManager, address(this), uint128(-delta.amount0()), false);
            poolKey.currency1.take(poolManager, address(this), uint128(delta.amount1()), false);
        } else {
            poolKey.currency1.settle(poolManager, address(this), uint128(-delta.amount1()), false);
            poolKey.currency0.take(poolManager, address(this), uint128(delta.amount0()), false);
        }

        returnData = abi.encode(delta.amount0(), delta.amount1());
    }

    function swap(address sender, uint256 amountIn) public {
        poolManager.unlock(abi.encode(sender, amountIn));
    }
}

// Base contract with shared functionality
abstract contract OpHookTestBase is Test {
    OpHook public opHook;
    IERC20 public usdc;
    IWETH9 public weth;
    IPermit2 public permit2;
    IPoolManager public poolManager;
    UniversalRouter public router;

    address public weth_;
    address public usdc_;
    address public permit2_;
    address public poolManager_;
    address public universalRouter_;
    address public wethUniPool_;

    IOption public option1;
    IOption public option2;
    IOption public option3;
    address public option1_;
    address public option2_;
    address public option3_;

    PoolKey public poolKey1;
    PoolKey public poolKey2;

    YieldVault public vault;

    uint256 public networkFork;

    // Strike prices — set per chain before calling _setupCommon
    uint96 public strike1 = 3600e18;
    uint96 public strike2 = 4000e18;
    uint96 public strike3 = 5000e18;

    function _setupCommon() internal {
        deal(address(this), 10000e20 ether);
        deal(usdc_, address(this), 1000e6);

        weth = IWETH9(weth_);
        usdc = IERC20(usdc_);
        permit2 = IPermit2(permit2_);
        poolManager = IPoolManager(poolManager_);

        uint40 expiration = uint40(block.timestamp + 30 days);
        Redemption r = new Redemption("", "", weth_, usdc_, expiration, 1e22, false);
        Option o = new Option("", "", address(r));

        // Deploy factory
        OptionFactory factory = new OptionFactory(address(r), address(o), 0.0001e18);

        option1_ = factory.createOption(weth_, usdc_, expiration, strike1, false);
        option2_ = factory.createOption(weth_, usdc_, expiration, strike2, false);
        option3_ = factory.createOption(weth_, usdc_, expiration, strike3, false);

        option1 = IOption(option1_);
        option2 = IOption(option2_);
        option3 = IOption(option3_);

        uint160 flags = Hooks.BEFORE_ADD_LIQUIDITY_FLAG | Hooks.BEFORE_SWAP_FLAG | Hooks.BEFORE_DONATE_FLAG
            | Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG;

        bytes memory constructorArgs = abi.encode(poolManager_, permit2_);

        (address hookAddress, bytes32 salt) =
            HookMiner.find(address(this), flags, type(OpHook).creationCode, constructorArgs);

        opHook = new OpHook{ salt: salt }(poolManager_, permit2_);

        address opHook_ = address(opHook);

        // Deploy BlackScholes pricing
        BlackScholes bs = new BlackScholes();

        // Deploy vault: collateral = WETH, pricing = BlackScholes, oracle = wethUniPool
        vault = new YieldVault(
            IERC20(weth_),
            "Greek WETH Vault",
            "gWETH",
            address(factory),
            address(bs),
            wethUniPool_,
            usdc_,
            1800 // 30 min TWAP
        );
        vault.setupFactoryApproval();
        vault.addHook(opHook_);
        vault.whitelistOption(option1_, true);
        vault.whitelistOption(option2_, true);
        vault.whitelistOption(option3_, true);

        // LP deposits collateral into vault
        deal(weth_, address(this), 1000e18);
        weth.approve(address(vault), 1000e18);
        vault.deposit(1000e18, address(this));

        // Init pools with vault
        address vault_ = address(vault);
        poolKey1 = opHook.initPool(option1_, usdc_, 3000, vault_);
        poolKey2 = opHook.initPool(option2_, usdc_, 3000, vault_);

        console.log("Hook Address (expected)", hookAddress);
        console.log("Hook Address (actual)", opHook_);

        // Fund vault with USDC for buybacks
        deal(usdc_, address(vault), 1000e18);
        deal(usdc_, poolManager_, 1000e18);

        usdc.approve(address(factory), 1000e6);
        usdc.approve(opHook_, 1000e6);
        usdc.approve(poolManager_, 1000e6);
        usdc.approve(permit2_, 1000e6);
        weth.approve(address(factory), 1000e18);
        weth.approve(address(permit2_), 1000e18);

        permit2.approve(usdc_, poolManager_, type(uint160).max, uint48(block.timestamp + 1 days));
        permit2.approve(usdc_, opHook_, type(uint160).max, uint48(block.timestamp + 1 days));

        router = UniversalRouter(payable(universalRouter_));
        deal(usdc_, address(this), 1000e6);

        // Approve router and permit2
        usdc.approve(address(router), 1000e6);
        permit2.approve(address(usdc), address(router), type(uint160).max, uint48(block.timestamp + 1 days));
    }

    function testQuote() public {
        (uint256 optionsOut, uint256 unitPrice) = vault.getQuote(option1_, 100e6, true);
        console.log("Options out for 100 USDC:", optionsOut);
        console.log("Unit price (USDC):", unitPrice);
        assertGt(optionsOut, 0);
        assertGt(unitPrice, 0);
    }

    function testCollateralPrice() public {
        uint256 price = vault.getCollateralPrice();
        console.log("Collateral price (TWAP):", price / 1e18);
        assertGt(price, 0);
    }

    function testSwapCallback() public {
        bool usdcIsZero = Currency.unwrap(poolKey1.currency0) == usdc_;
        bool zeroForOne = usdcIsZero;

        SwapCallback swapCallback = new SwapCallback(poolManager, opHook, poolKey1, zeroForOne);
        address swapcb = address(swapCallback);

        deal(usdc_, swapcb, 1000e6);
        deal(usdc_, address(this), 1000e6);
        deal(weth_, address(this), 1000e18);

        usdc.approve(permit2_, type(uint256).max);
        usdc.approve(swapcb, type(uint256).max);
        usdc.approve(poolManager_, type(uint256).max);
        permit2.approve(address(usdc), poolManager_, type(uint160).max, uint48(block.timestamp + 1 days));
        permit2.approve(address(usdc), swapcb, type(uint160).max, uint48(block.timestamp + 1 days));

        vm.startPrank(swapcb);
        usdc.approve(permit2_, type(uint256).max);
        usdc.approve(poolManager_, type(uint256).max);
        permit2.approve(address(usdc), poolManager_, type(uint160).max, uint48(block.timestamp + 1 days));
        vm.stopPrank();

        swapCallback.swap(address(this), 1e6);
    }

    function testRouterSwap() public virtual {
        bool usdcIsZero = Currency.unwrap(poolKey1.currency0) == usdc_;
        bool zeroForOne = usdcIsZero;
        Currency inputCurrency = usdcIsZero ? poolKey1.currency0 : poolKey1.currency1;
        Currency outputCurrency = usdcIsZero ? poolKey1.currency1 : poolKey1.currency0;

        bytes memory commands = abi.encodePacked(uint8(0x10));
        bytes memory actions =
            abi.encodePacked(uint8(Actions.SWAP_EXACT_IN_SINGLE), uint8(Actions.SETTLE_ALL), uint8(Actions.TAKE_ALL));

        bytes[] memory params = new bytes[](3);
        params[0] = abi.encode(
            IV4Router.ExactInputSingleParams({
                poolKey: poolKey1, zeroForOne: zeroForOne, amountIn: 1e6, amountOutMinimum: 0, hookData: bytes("")
            })
        );
        params[1] = abi.encode(inputCurrency, type(uint256).max);
        params[2] = abi.encode(outputCurrency, 0);

        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(actions, params);

        router.execute(commands, inputs, block.timestamp + 20);
    }
}

contract Mainnet is OpHookTestBase {
    function setUp() public {
        string memory rpc = "https://reth-ethereum.ithaca.xyz/rpc";
        networkFork = vm.createSelectFork(rpc, 23359458);
        weth_ = ConstantsMainnet.WETH;
        usdc_ = ConstantsMainnet.USDC;
        permit2_ = ConstantsMainnet.PERMIT2;
        poolManager_ = ConstantsMainnet.POOLMANAGER;
        universalRouter_ = ConstantsMainnet.UNIVERSALROUTER;
        wethUniPool_ = ConstantsMainnet.WETH_UNI_POOL;
        _setupCommon();
    }
}

// Base-specific tests
contract Base is OpHookTestBase {
    function setUp() public {
        string memory rpc = "https://mainnet.base.org";
        networkFork = vm.createSelectFork(rpc, 43190000);
        weth_ = ConstantsBase.WETH;
        usdc_ = ConstantsBase.USDC;
        permit2_ = ConstantsBase.PERMIT2;
        poolManager_ = ConstantsBase.POOLMANAGER;
        universalRouter_ = ConstantsBase.UNIVERSALROUTER;
        wethUniPool_ = ConstantsBase.WETH_UNI_POOL;
        // ETH ~$2039 at block 43190000
        strike1 = 2100e18;
        strike2 = 2300e18;
        strike3 = 2500e18;
        _setupCommon();
    }
}
