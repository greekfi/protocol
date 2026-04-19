// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;
import { Script } from "forge-std/Script.sol";
import { MockERC20 } from "../contracts/mocks/MockERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract FundMaker is Script {
    address constant WETH = 0x6C7a2C02f2B9A7b9aC30df8334a56Daae5A84531;
    address constant USDC = 0x200a591331FeEcfd25976D135E2D4C00Fa4Bb42e;
    address constant MAKER = 0x70997970C51812dc3A010C7d01b50e0d17dc79C8;
    address constant BEBOP = 0xbbbbbBB520d69a9775E85b458C58c648259FAD5F;
    uint256 constant MAKER_PK = 0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d;

    function run() external {
        vm.startBroadcast();
        MockERC20(WETH).mint(MAKER, 100e18);
        MockERC20(USDC).mint(MAKER, 1_000_000e6);
        vm.stopBroadcast();

        vm.startBroadcast(MAKER_PK);
        IERC20(WETH).approve(BEBOP, type(uint256).max);
        IERC20(USDC).approve(BEBOP, type(uint256).max);
        vm.stopBroadcast();
    }
}
