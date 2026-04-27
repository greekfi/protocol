// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { Test, console } from "forge-std/Test.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { Factory } from "../contracts/Factory.sol";
import { Collateral } from "../contracts/Collateral.sol";
import { Option } from "../contracts/Option.sol";
import { CreateParams } from "../contracts/interfaces/IFactory.sol";
import { MockPriceOracle } from "./mocks/MockPriceOracle.sol";

import { V4SettlementSwapper } from "../contracts/periphery/V4SettlementSwapper.sol";
import { IPoolManager } from "v4-core/interfaces/IPoolManager.sol";

/// @notice End-to-end cash-settlement on a live fork. Holders opt in, we trigger the
///         swap via `V4SettlementSwapper` against the real Uniswap v4 WETH/USDC pool,
///         holders pull USDC. `CHAIN=mainnet|arbitrum|base` selects the fork.
contract CashSettlementForkTest is Test {
    struct ChainCfg {
        address weth;
        address usdc;
        address v4PoolManager;
        uint24 v4Fee;
        int24 v4TickSpacing;
        address v4Hooks;
        string rpcAlias;
    }

    Factory public factory;
    Option public opt;
    Collateral public coll;
    MockPriceOracle public oracle;
    V4SettlementSwapper public swapper;

    address public alice = address(0xA11CE);
    address public bob = address(0xB0B);
    address public carol = address(0xCA401);

    uint256 public constant AMOUNT_PER_HOLDER = 0.001 ether; // small — any pool can handle
    uint96 public constant STRIKE = 1000e18; // deep ITM at any sane WETH price
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
        } else {
            cfg = ChainCfg({
                weth: 0x4200000000000000000000000000000000000006,
                usdc: 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913,
                v4PoolManager: 0x498581fF718922c3f8e6A244956aF099B2652b2b,
                v4Fee: 500,
                v4TickSpacing: 10,
                v4Hooks: address(0),
                rpcAlias: "base"
            });
        }
        vm.createSelectFork(cfg.rpcAlias);

        // Deploy protocol.
        Collateral collTpl = new Collateral("Short", "S");
        Option optTpl = new Option("Long", "L");
        factory = new Factory(address(collTpl), address(optTpl));

        // Deploy the swapper pointing at the chain's v4 PoolManager.
        swapper = new V4SettlementSwapper(IPoolManager(cfg.v4PoolManager), cfg.v4Fee, cfg.v4TickSpacing, cfg.v4Hooks);

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

        // Fund this contract with WETH and mint option tokens out to three holders.
        uint256 totalColl = 3 * AMOUNT_PER_HOLDER;
        deal(cfg.weth, address(this), totalColl);
        IERC20(cfg.weth).approve(address(factory), type(uint256).max);
        factory.approve(cfg.weth, uint160(totalColl));

        _mintTo(alice, AMOUNT_PER_HOLDER);
        _mintTo(bob, AMOUNT_PER_HOLDER);
        _mintTo(carol, AMOUNT_PER_HOLDER);

        // Move past expiry.
        vm.warp(block.timestamp + 8 days);
    }

    function _mintTo(address to, uint256 amount) internal {
        opt.mint(amount);
        opt.transfer(to, amount);
    }

    function test_fork_cashSettlement_endToEnd() public {
        // Default is cash. Only carol opts into in-kind collateral; alice and bob stay default.
        vm.prank(carol); coll.requestCollateral();

        uint256 reservedOptions = coll.totalCollateralReservedOptions();
        assertEq(reservedOptions, AMOUNT_PER_HOLDER);

        // Trigger the real v4 swap.
        coll.convertResidualToConsideration(swapper, 1, "");

        assertTrue(coll.cashSwapCompleted());
        uint256 perWad = coll.cashConsiderationPerOptionWad();
        assertGt(perWad, 0);
        console.log("cashConsiderationPerOptionWad (USDC per option):", perWad);

        // alice claims cash (default).
        uint256 aliceBefore = IERC20(cfg.usdc).balanceOf(alice);
        vm.prank(alice);
        opt.claim(AMOUNT_PER_HOLDER);
        uint256 aliceAfter = IERC20(cfg.usdc).balanceOf(alice);
        assertGt(aliceAfter - aliceBefore, 0);
        console.log("alice USDC received:", aliceAfter - aliceBefore);

        // bob claims cash (default).
        vm.prank(bob);
        opt.claim(AMOUNT_PER_HOLDER);
        uint256 bobRec = IERC20(cfg.usdc).balanceOf(bob);
        assertApproxEqAbs(bobRec, aliceAfter - aliceBefore, 1);

        // carol gets WETH (opted into collateral).
        vm.prank(carol);
        opt.claim(AMOUNT_PER_HOLDER);
        uint256 carolWeth = IERC20(cfg.weth).balanceOf(carol);
        assertGt(carolWeth, 0);
        console.log("carol WETH residual:", carolWeth);
    }

    function test_fork_cashSettlement_allDefaultCash() public {
        // Nobody opts in — default is cash across the board.

        uint256 g = gasleft();
        coll.convertResidualToConsideration(swapper, 1, "");
        uint256 swapGas = g - gasleft();
        console.log("convertResidualToConsideration gas:", swapGas);

        vm.prank(alice); opt.claim(AMOUNT_PER_HOLDER);
        vm.prank(bob);   opt.claim(AMOUNT_PER_HOLDER);
        vm.prank(carol); opt.claim(AMOUNT_PER_HOLDER);

        uint256 a = IERC20(cfg.usdc).balanceOf(alice);
        uint256 b = IERC20(cfg.usdc).balanceOf(bob);
        uint256 c = IERC20(cfg.usdc).balanceOf(carol);
        assertApproxEqAbs(a, b, 1);
        assertApproxEqAbs(b, c, 1);
        console.log("each holder USDC:", a);
    }

    function _eq(string memory a, string memory b) private pure returns (bool) {
        return keccak256(bytes(a)) == keccak256(bytes(b));
    }
}
