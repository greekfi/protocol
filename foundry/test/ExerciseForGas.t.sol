// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { Test, console } from "forge-std/Test.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { Factory } from "../contracts/Factory.sol";
import { Collateral } from "../contracts/Collateral.sol";
import { Option } from "../contracts/Option.sol";
import { CreateParams } from "../contracts/interfaces/IFactory.sol";
import { MockPriceOracle } from "./mocks/MockPriceOracle.sol";

import { IPoolManager } from "v4-core/interfaces/IPoolManager.sol";
import { IUnlockCallback } from "v4-core/interfaces/callback/IUnlockCallback.sol";
import { PoolKey } from "v4-core/types/PoolKey.sol";
import { SwapParams } from "v4-core/types/PoolOperation.sol";
import { BalanceDelta } from "v4-core/types/BalanceDelta.sol";
import { Currency } from "v4-core/types/Currency.sol";
import { IHooks } from "v4-core/interfaces/IHooks.sol";

/// @title  ExerciseForGasTest — gas bench for post-expiry `exerciseFor` flows
/// @notice Measured scenarios:
///         A  single `exerciseFor`
///         B  100-holder batch, keeper pre-funded with USDC — external loop
///         D  100-holder batch via the `address[] / uint256[]` array overload
///         C  100-holder batch using Uniswap v4 flash accounting:
///            one `swap` inside `unlock` borrows USDC (paid back in WETH from the
///            ITM exercise), no separate flash-loan provider needed.
///
/// Chain is selected via `CHAIN=mainnet|arbitrum|base`. Fork RPC is resolved from
/// foundry.toml (`rpc_endpoints`).
contract ExerciseForGasTest is Test {
    struct ChainCfg {
        address weth;
        address usdc;
        address v4PoolManager;
        // PoolKey fields for the WETH/USDC v4 pool we route through.
        uint24 v4Fee;
        int24 v4TickSpacing;
        address v4Hooks;
        string rpcAlias;
    }

    Factory public factory;
    Option public opt;
    Collateral public coll;
    MockPriceOracle public oracle;

    address public keeper = address(0xBEEF);
    address[] public holders;

    uint256 public constant NUM_HOLDERS = 100;
    uint256 public constant AMOUNT_PER_HOLDER = 0.0001 ether; // 0.0001 WETH each → 0.01 WETH total
    uint96 public constant STRIKE = 1000e18;
    uint256 public constant SPOT = 3000e18;

    ChainCfg public cfg;

    function setUp() public {
        string memory chain = vm.envOr("CHAIN", string("base"));
        if (_eq(chain, "mainnet")) {
            cfg = ChainCfg({
                weth: 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2,
                usdc: 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48,
                v4PoolManager: 0x000000000004444c5dc75cB358380D2e3dE08A90,
                v4Fee: 500,
                v4TickSpacing: 10,
                v4Hooks: address(0),
                rpcAlias: "mainnet"
            });
        } else if (_eq(chain, "arbitrum")) {
            cfg = ChainCfg({
                weth: 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1,
                usdc: 0xaf88d065e77c8cC2239327C5EDb3A432268e5831,
                v4PoolManager: 0x360E68faCcca8cA495c1B759Fd9EEe466db9FB32,
                v4Fee: 500,
                v4TickSpacing: 10,
                v4Hooks: address(0),
                rpcAlias: "arbitrum"
            });
        } else if (_eq(chain, "base")) {
            cfg = ChainCfg({
                weth: 0x4200000000000000000000000000000000000006,
                usdc: 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913,
                v4PoolManager: 0x498581fF718922c3f8e6A244956aF099B2652b2b,
                v4Fee: 500,
                v4TickSpacing: 10,
                v4Hooks: address(0),
                rpcAlias: "base"
            });
        } else {
            revert("CHAIN must be mainnet|arbitrum|base");
        }

        vm.createSelectFork(cfg.rpcAlias);

        // 1. Deploy protocol fresh on fork.
        Collateral collTpl = new Collateral("Short Option", "SHORT");
        Option optTpl = new Option("Long Option", "LONG");
        factory = new Factory(address(collTpl), address(optTpl));

        // 2. Create a WETH/USDC call, oracle = MockPriceOracle (pre-settled ITM at SPOT).
        uint40 expiration = uint40(block.timestamp + 7 days);
        oracle = new MockPriceOracle(expiration);
        oracle.setPrice(SPOT);

        CreateParams memory p = CreateParams({
            collateral: cfg.weth,
            consideration: cfg.usdc,
            expirationDate: expiration,
            strike: STRIKE,
            isPut: false,
            isEuro: false,
            oracleSource: address(oracle),
            twapWindow: 0
        });
        opt = Option(factory.createOption(p));
        coll = Collateral(opt.coll());

        // 3. Fund this contract with WETH, mint to NUM_HOLDERS addresses.
        uint256 totalColl = NUM_HOLDERS * AMOUNT_PER_HOLDER;
        deal(cfg.weth, address(this), totalColl);
        IERC20(cfg.weth).approve(address(factory), type(uint256).max);
        factory.approve(cfg.weth, uint160(totalColl));

        for (uint256 i = 0; i < NUM_HOLDERS; i++) {
            address h = address(uint160(0x1000 + i));
            holders.push(h);
            opt.mint(AMOUNT_PER_HOLDER);
            opt.transfer(h, AMOUNT_PER_HOLDER);
        }

        // 4. Move past expiry so exerciseFor is callable.
        vm.warp(block.timestamp + 8 days);
    }

    // ============ Scenario A — single exerciseFor ============

    function test_A_singleExerciseFor() public {
        address holder = holders[0];
        uint256 consAmount = coll.toNeededConsideration(AMOUNT_PER_HOLDER);
        deal(cfg.usdc, keeper, consAmount);

        vm.startPrank(keeper);
        IERC20(cfg.usdc).approve(address(factory), type(uint256).max);
        factory.approve(cfg.usdc, uint160(consAmount));

        uint256 g = gasleft();
        opt.exerciseFor(holder, AMOUNT_PER_HOLDER, keeper);
        uint256 used = g - gasleft();
        vm.stopPrank();

        console.log("[A] single exerciseFor gas:", used);
    }

    // ============ Scenario B — 100-holder batch, keeper has USDC (external loop) ============

    function test_B_batchExerciseFor_keeperFunded() public {
        uint256 consPer = coll.toNeededConsideration(AMOUNT_PER_HOLDER);
        uint256 totalCons = consPer * NUM_HOLDERS;
        address kkeeper = address(this);
        deal(cfg.usdc, kkeeper, totalCons);
        IERC20(cfg.usdc).approve(address(factory), type(uint256).max);
        factory.approve(cfg.usdc, type(uint160).max);

        uint256 g = gasleft();
        for (uint256 i = 0; i < NUM_HOLDERS; i++) {
            opt.exerciseFor(holders[i], AMOUNT_PER_HOLDER, kkeeper);
        }
        uint256 used = g - gasleft();

        console.log("[B] batch x100 exerciseFor gas:", used);
        console.log("[B] gas per holder:", used / NUM_HOLDERS);
    }

    // ============ Scenario D — single-tx batch via array overload ============

    function test_D_batchExerciseFor_arrayOverload() public {
        uint256 consPer = coll.toNeededConsideration(AMOUNT_PER_HOLDER);
        uint256 totalCons = consPer * NUM_HOLDERS;
        address kkeeper = address(this);
        deal(cfg.usdc, kkeeper, totalCons);
        IERC20(cfg.usdc).approve(address(factory), type(uint256).max);
        factory.approve(cfg.usdc, type(uint160).max);

        address[] memory hs = new address[](NUM_HOLDERS);
        uint256[] memory amts = new uint256[](NUM_HOLDERS);
        for (uint256 i = 0; i < NUM_HOLDERS; i++) {
            hs[i] = holders[i];
            amts[i] = AMOUNT_PER_HOLDER;
        }

        uint256 g = gasleft();
        opt.exerciseFor(hs, amts, kkeeper);
        uint256 used = g - gasleft();

        console.log("[D] array overload x100 exerciseFor gas:", used);
        console.log("[D] gas per holder:", used / NUM_HOLDERS);
    }

    // ============ Scenario C — Uniswap v4 flash accounting + batch exerciseFor ============

    function test_C_flashBatchExerciseFor_v4() public {
        V4FlashExerciser fx = new V4FlashExerciser(cfg, address(factory), address(opt));

        address[] memory hs = new address[](NUM_HOLDERS);
        uint256[] memory amts = new uint256[](NUM_HOLDERS);
        for (uint256 i = 0; i < NUM_HOLDERS; i++) {
            hs[i] = holders[i];
            amts[i] = AMOUNT_PER_HOLDER;
        }

        uint256 g = gasleft();
        fx.run(hs, amts);
        uint256 used = g - gasleft();

        console.log("[C] v4 flash+batch x100 gas:", used);
        console.log("[C] gas per holder:", used / NUM_HOLDERS);
        console.log("[C] fx WETH surplus:", IERC20(cfg.weth).balanceOf(address(fx)));
    }

    // ============ helpers ============

    function _eq(string memory a, string memory b) private pure returns (bool) {
        return keccak256(bytes(a)) == keccak256(bytes(b));
    }
}

/// @notice Keeper using Uniswap v4 flash accounting. Borrows USDC from the v4 pool via a
///         single `swap` inside `unlock`, runs the exerciseFor batch (which returns WETH),
///         then settles the WETH side back to the pool. No separate flash-loan provider.
contract V4FlashExerciser is IUnlockCallback {
    ExerciseForGasTest.ChainCfg public cfg;
    IPoolManager public pm;
    Factory public factory;
    Option public opt;
    Collateral public coll;

    // Min/max price limits from v4-core TickMath — cover the whole price range.
    uint160 internal constant MIN_SQRT_PRICE_PLUS_1 = 4295128740;
    uint160 internal constant MAX_SQRT_PRICE_MINUS_1 = 1461446703485210103287273052203988822378723970341;

    struct CallbackData {
        address[] holders;
        uint256[] amounts;
        uint256 usdcNeeded;
    }

    constructor(ExerciseForGasTest.ChainCfg memory cfg_, address factory_, address opt_) {
        cfg = cfg_;
        pm = IPoolManager(cfg_.v4PoolManager);
        factory = Factory(factory_);
        opt = Option(opt_);
        coll = Collateral(opt.coll());
    }

    /// @notice Entry point. Figures out how much USDC the batch needs, then opens a v4 unlock.
    function run(address[] calldata holders_, uint256[] calldata amounts_) external {
        require(holders_.length == amounts_.length, "len");

        uint256 n = holders_.length;
        uint256 consPer = coll.toNeededConsideration(amounts_[0]);
        uint256 usdcNeeded = consPer * n;

        CallbackData memory data = CallbackData({ holders: holders_, amounts: amounts_, usdcNeeded: usdcNeeded });
        pm.unlock(abi.encode(data));
    }

    /// @notice v4 unlock callback — all flash-accounting happens here.
    ///         Flow:
    ///           1. swap(WETH/USDC, exact-output = usdcNeeded USDC)
    ///              → pool owes us `usdcNeeded` USDC; we owe pool `wethIn` WETH
    ///           2. take(USDC, self, usdcNeeded) — pool pays us the USDC
    ///           3. exerciseFor(batch) — pays USDC via factory, receives WETH
    ///           4. sync(WETH); transfer `wethIn` WETH to poolManager; settle()
    ///              → closes the WETH debt. Surplus WETH stays in this contract.
    function unlockCallback(bytes calldata raw) external override returns (bytes memory) {
        require(msg.sender == address(pm), "only pm");
        CallbackData memory data = abi.decode(raw, (CallbackData));

        // Canonical PoolKey: currency0 = lower address.
        bool wethIsToken0 = cfg.weth < cfg.usdc;
        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(wethIsToken0 ? cfg.weth : cfg.usdc),
            currency1: Currency.wrap(wethIsToken0 ? cfg.usdc : cfg.weth),
            fee: cfg.v4Fee,
            tickSpacing: cfg.v4TickSpacing,
            hooks: IHooks(cfg.v4Hooks)
        });

        // We want USDC out, WETH in.
        //   - If WETH is token0, then "zeroForOne = true" swaps token0→token1 (WETH→USDC). ✓
        //   - If WETH is token1, then "zeroForOne = false" swaps token1→token0 (WETH→USDC). ✓
        bool zeroForOne = wethIsToken0;
        // v4 convention: amountSpecified > 0 = exactOutput; < 0 = exactInput.
        // Here exactOutput of USDC = positive.
        SwapParams memory sp = SwapParams({
            zeroForOne: zeroForOne,
            amountSpecified: int256(data.usdcNeeded),
            sqrtPriceLimitX96: zeroForOne ? MIN_SQRT_PRICE_PLUS_1 : MAX_SQRT_PRICE_MINUS_1
        });
        BalanceDelta delta = pm.swap(key, sp, "");

        // Pull the USDC out of the PoolManager now — creates the net balance we'll consume.
        pm.take(Currency.wrap(cfg.usdc), address(this), data.usdcNeeded);

        // Wire factory approvals + run the exerciseFor batch (array overload).
        IERC20(cfg.usdc).approve(address(factory), type(uint256).max);
        factory.approve(cfg.usdc, uint160(data.usdcNeeded));
        opt.exerciseFor(data.holders, data.amounts, address(this));

        // Settle the WETH debt. v4 `sync` + token transfer + `settle` clears the negative delta.
        // `wethIn` is the amount the swap debited from us on the WETH side.
        int128 wethDelta128 = wethIsToken0 ? _amount0(delta) : _amount1(delta);
        // The swap returns the delta in our favour: negative means we owe that much WETH.
        uint256 wethIn = uint256(uint128(-wethDelta128));

        pm.sync(Currency.wrap(cfg.weth));
        IERC20(cfg.weth).transfer(address(pm), wethIn);
        pm.settle();

        return "";
    }

    function _amount0(BalanceDelta delta) private pure returns (int128 a) {
        assembly { a := sar(128, delta) }
    }

    function _amount1(BalanceDelta delta) private pure returns (int128 a) {
        assembly { a := signextend(15, delta) }
    }
}
