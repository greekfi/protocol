// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { Test, console } from "forge-std/Test.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { Factory } from "../contracts/Factory.sol";
import { Collateral } from "../contracts/Collateral.sol";
import { Option } from "../contracts/Option.sol";
import { CreateParams } from "../contracts/interfaces/IFactory.sol";
import { MockPriceOracle } from "./mocks/MockPriceOracle.sol";

import { UniversalRouterSwapper, IUniversalRouter } from "../contracts/periphery/UniversalRouterSwapper.sol";

/// @notice End-to-end cash-settlement against Uniswap's Universal Router on a live fork.
///         The swapper is venue-agnostic (routes through v2/v3/v4 via UR commands). This
///         test encodes a V3_SWAP_EXACT_IN single-hop as the `routeHint`, which mirrors what
///         a keeper's off-chain routing service would produce in production.
contract UniversalRouterSwapperForkTest is Test {
    struct ChainCfg {
        address weth;
        address usdc;
        address universalRouter;
        uint24 v3Fee;
        string rpcAlias;
    }

    // Universal Router command codes (from @uniswap/universal-router/contracts/libraries/Commands.sol).
    bytes1 internal constant V3_SWAP_EXACT_IN = 0x00;

    Factory public factory;
    Option public opt;
    Collateral public coll;
    MockPriceOracle public oracle;
    UniversalRouterSwapper public swapper;

    address public alice = address(0xA11CE);
    address public bob = address(0xB0B);

    uint256 public constant AMOUNT_PER_HOLDER = 0.001 ether;
    uint96 public constant STRIKE = 1000e18;
    uint256 public constant SPOT = 3000e18;

    ChainCfg public cfg;

    function setUp() public {
        string memory chain = vm.envOr("CHAIN", string("base"));
        if (_eq(chain, "mainnet")) {
            cfg = ChainCfg({
                weth: 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2,
                usdc: 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48,
                universalRouter: 0x66a9893cC07D91D95644AEDD05D03f95e1dBA8Af,
                v3Fee: 500,
                rpcAlias: "mainnet"
            });
        } else if (_eq(chain, "arbitrum")) {
            cfg = ChainCfg({
                weth: 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1,
                usdc: 0xaf88d065e77c8cC2239327C5EDb3A432268e5831,
                universalRouter: 0x5E325eDA8064b456f4781070C0738d849c824258,
                v3Fee: 500,
                rpcAlias: "arbitrum"
            });
        } else {
            cfg = ChainCfg({
                weth: 0x4200000000000000000000000000000000000006,
                usdc: 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913,
                universalRouter: 0x3fC91A3afd70395Cd496C647d5a6CC9D4B2b7FAD,
                v3Fee: 500,
                rpcAlias: "base"
            });
        }
        vm.createSelectFork(cfg.rpcAlias);

        Collateral collTpl = new Collateral("Short", "S");
        Option optTpl = new Option("Long", "L");
        factory = new Factory(address(collTpl), address(optTpl));
        swapper = new UniversalRouterSwapper(IUniversalRouter(cfg.universalRouter));

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

        uint256 totalColl = 2 * AMOUNT_PER_HOLDER;
        deal(cfg.weth, address(this), totalColl);
        IERC20(cfg.weth).approve(address(factory), type(uint256).max);
        factory.approve(cfg.weth, uint160(totalColl));

        opt.mint(AMOUNT_PER_HOLDER); opt.transfer(alice, AMOUNT_PER_HOLDER);
        opt.mint(AMOUNT_PER_HOLDER); opt.transfer(bob, AMOUNT_PER_HOLDER);

        vm.warp(block.timestamp + 8 days);
    }

    function test_fork_universalRouter_v3Route() public {
        // Default is cash — neither alice nor bob opts into anything, so the full reserve swaps.

        // Build the Universal Router command payload for a v3 exact-in single-hop:
        //   commands = [V3_SWAP_EXACT_IN]
        //   inputs[0] = (recipient, amountIn, amountOutMin, path, payerIsUser=false)
        //
        // Collateral forwards (tokenIn=WETH, tokenOut=USDC, amountIn=wethToSwap) to the swapper;
        // the swapper transfers tokenIn to the router first, so the inner swap uses
        // payerIsUser=false (the router spends its own balance).
        bytes memory commands = abi.encodePacked(V3_SWAP_EXACT_IN);
        bytes[] memory inputs = new bytes[](1);

        // amountIn here is what Collateral will actually send. We can't know the exact value
        // off-chain without reading settlement math, so we pass `type(uint256).max` which the
        // router interprets as "use actual balance". This is the `CONTRACT_BALANCE` sentinel
        // in UR — spends whatever was transferred to the router.
        // (Uniswap's Constants.CONTRACT_BALANCE = 1 << 255)
        uint256 CONTRACT_BALANCE = 1 << 255;

        // path = tokenIn || fee (3 bytes) || tokenOut
        bytes memory path = abi.encodePacked(cfg.weth, cfg.v3Fee, cfg.usdc);

        inputs[0] = abi.encode(
            address(swapper), // recipient of USDC — swapper forwards to Collateral
            CONTRACT_BALANCE, // amountIn — use whatever got transferred in
            uint256(1),       // amountOutMin — swapper's own minOut guard validates this upstream
            path,
            false             // payerIsUser — false = pay from router's own balance
        );

        bytes memory routeHint = abi.encode(commands, inputs);

        uint256 g = gasleft();
        coll.convertResidualToConsideration(swapper, 1, routeHint);
        uint256 swapGas = g - gasleft();

        assertTrue(coll.cashSwapCompleted());
        uint256 perWad = coll.cashConsiderationPerOptionWad();
        assertGt(perWad, 0);
        console.log("UR-backed swap gas:", swapGas);
        console.log("cashConsiderationPerOptionWad:", perWad);

        vm.prank(alice); opt.claim(AMOUNT_PER_HOLDER);
        vm.prank(bob);   opt.claim(AMOUNT_PER_HOLDER);

        uint256 aliceUsdc = IERC20(cfg.usdc).balanceOf(alice);
        uint256 bobUsdc = IERC20(cfg.usdc).balanceOf(bob);
        assertApproxEqAbs(aliceUsdc, bobUsdc, 1);
        console.log("each holder USDC (v3 route via UR):", aliceUsdc);
    }

    function _eq(string memory a, string memory b) private pure returns (bool) {
        return keccak256(bytes(a)) == keccak256(bytes(b));
    }
}
