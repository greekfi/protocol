// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {OpHook, CurrentOptionPrice} from "../contracts/OpHook.sol";
import {Option, Redemption} from "../contracts/Option.sol";
import {HookMiner} from "@uniswap/v4-periphery/src/utils/HookMiner.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";

import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IWETH9} from "@uniswap/v4-periphery/src/interfaces/external/IWETH9.sol";
import {UniversalRouter} from "@uniswap/universal-router/contracts/UniversalRouter.sol";
import {IV4Router} from "@uniswap/v4-periphery/src/interfaces/IV4Router.sol";
import {Actions} from "@uniswap/v4-periphery/src/libraries/Actions.sol";

import {CurrencySettler} from "@uniswap/v4-core/test/utils/CurrencySettler.sol";
import {SwapParams, PoolKey} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";

import {IPermit2} from "../contracts/interfaces/IPermit2.sol";
import {SafeCallback} from "./SafeCallback.sol";
import {NonzeroDeltaCount} from "@uniswap/v4-core/src/libraries/NonzeroDeltaCount.sol";
import {ConstantsMainnet} from "../contracts/ConstantsMainnet.sol";
import {ConstantsUnichain} from "../contracts/ConstantsUnichain.sol";
import {OptionPrice} from "../contracts/OptionPrice.sol";

import {IOption} from "../contracts/interfaces/IOption.sol";
import {OptionFactory} from "../contracts/OptionFactory.sol";


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

    function _unlockCallback(bytes calldata data) internal override returns (bytes memory) {
        (address sender) = abi.decode(data, (address));

        int256 amountIn = 1e6;
        SwapParams memory params = SwapParams({
            zeroForOne: zeroForOne,
            amountSpecified: -amountIn,
            sqrtPriceLimitX96: TickMath.MAX_SQRT_PRICE - 1
        });

        bytes memory d = bytes("");
        IERC20 usdc = IERC20(Currency.unwrap(zeroForOne ? poolKey.currency0 : poolKey.currency1));
        IERC20 option = IERC20(Currency.unwrap(zeroForOne ? poolKey.currency1 : poolKey.currency0));
        uint256 initBal = usdc.balanceOf(address(poolManager));

        if (zeroForOne) {
            poolKey.currency0.settle(poolManager, sender, 1e6, false);
        } else {
            poolKey.currency1.settle(poolManager, sender, 1e6, false);
        }
        console.log("delta", NonzeroDeltaCount.read());

        BalanceDelta delta = poolManager.swap(poolKey, params, d);
        console.log("delta0", delta.amount0());
        console.log("delta1", delta.amount1());
        console.log("delta", NonzeroDeltaCount.read());

        if (zeroForOne) {
            poolKey.currency1.take(poolManager, address(this), uint128(delta.amount1()), false);
        } else {
            poolKey.currency0.take(poolManager, address(this), uint128(delta.amount0()), false);
        }
        console.log("delta", NonzeroDeltaCount.read());
        console.log("option balance", option.balanceOf(address(poolManager)));
        console.log("option balance", option.balanceOf(address(this)));
        console.log("usdc balance", int256(usdc.balanceOf(address(poolManager))) - int256(initBal));
        console.log("usdc balance", usdc.balanceOf(address(sender)));
        console.log("option balance", option.balanceOf(address(sender)));

        return data;
    }

    function swap(address sender) public {
        poolManager.unlock(abi.encode(sender));
    }
}

// Base contract with shared functionality
abstract contract OpHookTestBase is Test {
    OpHook public opHook;
    IERC20 public usdc;
    IWETH9 public weth;
    IPermit2 public permit2;
    IPoolManager public poolManager;

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

    uint256 public networkFork;

    function _createOptions() internal {
    }

    function _deployHook() internal {
    }

    function _setupApprovals() internal {

    }

	function _setupCommon() internal {
		deal(address(this), 10000e20 ether);
		deal(usdc_, address(this), 1000e6);

		weth = IWETH9(weth_);
		usdc = IERC20(usdc_);
		permit2 = IPermit2(permit2_);
		poolManager = IPoolManager(poolManager_);


		uint256 expiration = block.timestamp + 30 days;
		Redemption r = new Redemption("","",weth_,usdc_,expiration,1e22, false);
		Option o = new Option("","",weth_,usdc_,expiration,1e22,false, address(r));
		OptionFactory factory = new OptionFactory(address(r), address(o));

		option1_ = factory.createOption(
			"OPT-WETH-USDC-3600-30D",
			"OPT-WETH-USDC-3600-30D",
			weth_,
			usdc_,
			expiration,
			3600e18,
			false
		);

		option2_ = factory.createOption(
			"OPT-WETH-USDC-4000-30D",
			"OPT-WETH-USDC-4000-30D",
			weth_,
			usdc_,
			expiration,
			4000e18,
			false
		);


		option3_ = factory.createOption(
			"OPT-WETH-USDC-5000-30D",
			"OPT-WETH-USDC-5000-30D",
			weth_,
			usdc_,
			expiration,
			5000e18,
			false
		);

		option1 = IOption(option1_);
		option2 = IOption(option2_);
		option3 = IOption(option3_);


		uint160 flags = Hooks.BEFORE_ADD_LIQUIDITY_FLAG |
						Hooks.BEFORE_SWAP_FLAG |
						Hooks.BEFORE_DONATE_FLAG |
						Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG;

		bytes memory constructorArgs = abi.encode(
			poolManager_,
			permit2_
		);

		(address hookAddress, bytes32 salt) = HookMiner.find(
			address(this),
			flags,
			type(OpHook).creationCode,
			constructorArgs
		);

		opHook = new OpHook{salt: salt}(
			poolManager_,
			permit2_
		);
		opHook.setOptionPrice(address(new OptionPrice()));


		poolKey1 = opHook.initPool(option1_, usdc_, weth_, wethUniPool_, 3000);
		poolKey2 = opHook.initPool(option2_, usdc_, weth_, wethUniPool_, 3000);

		console.log("Hook Address (expected)", hookAddress);
		console.log("Hook Address (actual)", address(opHook));

		address opHook_ = address(opHook);

		deal(weth_, opHook_, 1000e18);
		deal(usdc_, opHook_, 1000e18);
		deal(usdc_, poolManager_, 1000e18);

		usdc.approve(opHook_, 1000e6);
		usdc.approve(poolManager_, 1000e6);
		usdc.approve(permit2_, 1000e6);
		usdc.approve(option1_, 1000e6);
		usdc.approve(option2_, 1000e6);
		usdc.approve(option3_, 1000e6);
		usdc.approve(option1.redemption_(), 1000e6);
		usdc.approve(option2.redemption_(), 1000e6);
		usdc.approve(option3.redemption_(), 1000e6);
		weth.approve(option1.redemption_(), 1000e6);
		weth.approve(option2.redemption_(), 1000e6);
		weth.approve(option3.redemption_(), 1000e6);

		permit2.approve(usdc_, poolManager_, type(uint160).max, uint48(block.timestamp + 1 days));
		permit2.approve(usdc_, opHook_, type(uint160).max, uint48(block.timestamp + 1 days));

		// Hook needs to approve WETH to Permit2 and then to redemption contracts for minting
		vm.startPrank(opHook_);
		weth.approve(address(permit2_), type(uint256).max);
		permit2.approve(weth_, option1.redemption_(), type(uint160).max, type(uint48).max);
		permit2.approve(weth_, option2.redemption_(), type(uint160).max, type(uint48).max);
		permit2.approve(weth_, option3.redemption_(), type(uint160).max, type(uint48).max);
		vm.stopPrank();
	}


	function testPrices() public {
        if (option3_ != address(0)) {
            opHook.initPool(option3_, usdc_, address(option3.collateral()), wethUniPool_, 3000);
        }
        CurrentOptionPrice[] memory prices = opHook.getPrices(weth_);
        console.log("price1", prices[0].price / 1e18);
        if (prices.length > 1) {
            console.log("price2", prices[1].price / 1e18);
        }
        if (prices.length > 2) {
            console.log("price3", prices[2].price / 1e18);
        }
    }

    function testPrice() public {
        address testOption = option3_ != address(0) ? option3_ : option1_;
        IOption opt = IOption(testOption);
        opHook.initPool(testOption, usdc_, address(opt.collateral()), wethUniPool_, 3000);

        console.log("strike", opt.strike());
        console.log("underlying", address(opt.collateral()));
        console.log("expiration", opt.expirationDate());
        console.log("isPut", opt.isPut());

        uint256 price = opHook.getPrice(testOption);
        CurrentOptionPrice[] memory prices = opHook.getPrices(weth_);
        console.log("price (direct)", price / 1e18);
        console.log("price1 (array)", prices[0].price / 1e18);
        if (prices.length > 1) {
            console.log("price2 (array)", prices[1].price / 1e18);
        }
    }

    function testSwapCallback() public virtual;
    function testRouterSwap() public virtual;
}

// Mainnet-specific tests
contract OpHookMainnetTest is OpHookTestBase {

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

    function testSwapCallback() public override {
        SwapCallback swapCallback = new SwapCallback(poolManager, opHook, poolKey1, false);
        address swapcb = address(swapCallback);
        deal(address(usdc), swapcb, 1000e18);
        deal(address(usdc), address(this), 1000e18);
        usdc.approve(permit2_, 1000e6);
        usdc.approve(swapcb, 1000e6);
        usdc.approve(poolManager_, 1000e6);
        swapCallback.swap(address(this));
    }

    function testRouterSwap() public override {
        UniversalRouter router = UniversalRouter(payable(universalRouter_));
        deal(usdc_, address(this), 1000e6);
        usdc.approve(address(router), 1000e6);
        usdc.approve(poolManager_, 1000e6);
        usdc.approve(permit2_, 1000e6);

        permit2.approve(address(usdc), address(router), type(uint160).max, uint48(block.timestamp + 1 days));
        permit2.approve(address(usdc), poolManager_, type(uint160).max, uint48(block.timestamp + 1 days));

        bytes memory commands = abi.encodePacked(uint8(0x10));
        bytes memory actions = abi.encodePacked(
            uint8(Actions.SWAP_EXACT_IN_SINGLE),
            uint8(Actions.SETTLE_ALL),
            uint8(Actions.TAKE_ALL)
        );

        bytes[] memory params = new bytes[](3);
        params[0] = abi.encode(
            IV4Router.ExactInputSingleParams({
                poolKey: poolKey1,
                zeroForOne: false,
                amountIn: 1e6,
                amountOutMinimum: 0,
                hookData: bytes("")
            })
        );
        params[1] = abi.encode(poolKey1.currency1, type(uint256).max);
        params[2] = abi.encode(poolKey1.currency0, 0);

        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(actions, params);

        router.execute(commands, inputs, block.timestamp + 20);

        console.log("option1 balance (this)", option1.balanceOf(address(this)));
        console.log("option1 balance (hook)", option1.balanceOf(address(opHook)));
        console.log("WETH balance (hook)", weth.balanceOf(address(opHook)));
        console.log("USDC balance (this)", usdc.balanceOf(address(this)));
        console.log("USDC balance (hook)", usdc.balanceOf(address(opHook)));
        console.log("USDC balance (poolManager)", usdc.balanceOf(poolManager_));
    }
}

// Unichain-specific tests
contract OpHookUnichainTest is OpHookTestBase {

    function setUp() public {
		string memory rpc = "https://unichain.drpc.org";
        networkFork = vm.createSelectFork(rpc, 27503100);
        weth_ = ConstantsUnichain.WETH;
        usdc_ = ConstantsUnichain.USDC;
        permit2_ = ConstantsUnichain.PERMIT2;
        poolManager_ = ConstantsUnichain.POOLMANAGER;
        universalRouter_ = ConstantsUnichain.UNIVERSALROUTER;
        wethUniPool_ = ConstantsUnichain.WETH_UNI_POOL;

		_setupCommon();
    }

    function testSwapCallback() public override {
        SwapCallback swapCallback = new SwapCallback(poolManager, opHook, poolKey1, true);
        address swapcb = address(swapCallback);
        deal(address(usdc), swapcb, 1000e18);
        deal(address(usdc), address(this), 1000e18);
        usdc.approve(permit2_, 1000e6);
        usdc.approve(swapcb, 1000e6);
        usdc.approve(poolManager_, 1000e6);
        swapCallback.swap(address(this));
    }

    function testRouterSwap() public override {
        UniversalRouter router = UniversalRouter(payable(universalRouter_));
        deal(usdc_, address(this), 1000e6);
        usdc.approve(address(router), 1000e6);
        permit2.approve(address(usdc), address(router), type(uint160).max, uint48(block.timestamp + 1 days));

        bytes memory commands = abi.encodePacked(uint8(0x10));
        bytes memory actions = abi.encodePacked(
            uint8(Actions.SWAP_EXACT_IN_SINGLE),
            uint8(Actions.SETTLE_ALL),
            uint8(Actions.TAKE_ALL)
        );

        bytes[] memory params = new bytes[](3);
        params[0] = abi.encode(
            IV4Router.ExactInputSingleParams({
                poolKey: poolKey1,
                zeroForOne: true,
                amountIn: 1e6,
                amountOutMinimum: 0,
                hookData: bytes("")
            })
        );
        params[1] = abi.encode(poolKey1.currency0, type(uint256).max);
        params[2] = abi.encode(poolKey1.currency1, 0);

        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(actions, params);

        router.execute(commands, inputs, block.timestamp + 20);

        console.log("option1 balance (this)", option1.balanceOf(address(this)));
        console.log("option1 balance (hook)", option1.balanceOf(address(opHook)));
        console.log("WETH balance (hook)", weth.balanceOf(address(opHook)));
        console.log("USDC balance (this)", usdc.balanceOf(address(this)));
        console.log("USDC balance (hook)", usdc.balanceOf(address(opHook)));
        console.log("USDC balance (poolManager)", usdc.balanceOf(poolManager_));
    }
}
