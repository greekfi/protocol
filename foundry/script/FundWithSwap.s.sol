// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

import { Script, console } from "forge-std/Script.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IWETH {
    function deposit() external payable;
    function balanceOf(address) external view returns (uint256);
    function approve(address, uint256) external returns (bool);
}

interface ISwapRouter02 {
    struct ExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
    }

    function exactInputSingle(ExactInputSingleParams calldata params) external payable returns (uint256);
}

/// @notice Fund scaffold-eth-default + user with real WETH + USDC on a forked Base chain.
///         Flow: anvil_setBalance (100 ETH) → wrap to WETH → swap half for USDC on Uniswap v3.
///
///         anvil --fork-url https://mainnet.base.org --chain-id 31337
///         forge script script/FundWithSwap.s.sol --broadcast --rpc-url http://localhost:8545 \
///             --account scaffold-eth-default --password localhost --legacy
///
///         (anvil_setBalance calls happen OUTSIDE this script — use a shell wrapper, or the
///         vm.deal cheatcode below does the equivalent during simulation.)
contract FundWithSwap is Script {
    // Base mainnet addresses
    address constant WETH = 0x4200000000000000000000000000000000000006;
    address constant USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    address constant SWAP_ROUTER_02 = 0x2626664c2603336E57B271c5C0b26F421741e481;

    // WETH/USDC 0.05% fee tier pool (deepest on Base)
    uint24 constant FEE = 500;

    // Recipients
    address constant DEPLOYER = 0xa0Ee7A142d267C1f36714E4a8F75612F20a79720; // scaffold-eth-default
    address constant USER = 0x5b5e727A7a78603ebF4f1652488830FC0843Df45;

    function run() external {
        // Give the deployer 200 ETH before broadcast (cheatcode, works in simulation)
        vm.deal(DEPLOYER, 200 ether);
        vm.deal(USER, 50 ether);

        vm.startBroadcast();

        // 1. Wrap 100 ETH → WETH
        IWETH(WETH).deposit{ value: 100 ether }();
        uint256 wethBal = IWETH(WETH).balanceOf(DEPLOYER);
        console.log("WETH balance after wrap:", wethBal);

        // 2. Approve router, swap 50 WETH → USDC
        IWETH(WETH).approve(SWAP_ROUTER_02, type(uint256).max);
        uint256 usdcOut = ISwapRouter02(SWAP_ROUTER_02)
            .exactInputSingle(
                ISwapRouter02.ExactInputSingleParams({
                tokenIn: WETH,
                tokenOut: USDC,
                fee: FEE,
                recipient: DEPLOYER,
                amountIn: 50 ether,
                amountOutMinimum: 0, // demo — no slippage protection
                sqrtPriceLimitX96: 0
            })
            );
        console.log("USDC received:", usdcOut);

        // 3. Send 10 WETH + 10k USDC to user
        IERC20(WETH).transfer(USER, 10 ether);
        IERC20(USDC).transfer(USER, 10_000e6);
        console.log("Seeded user with 10 WETH + 10k USDC");

        vm.stopBroadcast();

        console.log("=== Funding complete ===");
        console.log("Deployer WETH:", IWETH(WETH).balanceOf(DEPLOYER));
        console.log("Deployer USDC:", IERC20(USDC).balanceOf(DEPLOYER));
    }
}
