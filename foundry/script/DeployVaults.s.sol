// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

import { Script, console } from "forge-std/Script.sol";
import { YieldVault } from "../contracts/YieldVault.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @notice Deploy YieldVaults on the forked Base anvil.
///         forge script script/DeployVaults.s.sol --broadcast --rpc-url http://localhost:8545 \
///             --account scaffold-eth-default --password localhost --legacy \
///             --sig "run(address,address,address)" <factory> <weth> <usdc>
contract DeployVaults is Script {
    function run(address factory, address weth, address usdc) external {
        vm.startBroadcast();

        YieldVault wethVault = new YieldVault(IERC20(weth), "Greek WETH Vault", "gWETH", factory);
        YieldVault usdcVault = new YieldVault(IERC20(usdc), "Greek USDC Vault", "gUSDC", factory);

        console.log("WETH Vault:", address(wethVault));
        console.log("USDC Vault:", address(usdcVault));

        vm.stopBroadcast();
    }
}
