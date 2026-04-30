// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;
import { Script, console } from "forge-std/Script.sol";
import { YieldVault } from "../contracts/YieldVault.sol";
import { Factory } from "../contracts/Factory.sol";

contract FixVaults is Script {
    function run(address vault1, address vault2, address factory, address bebop) external {
        vm.startBroadcast();

        YieldVault v1 = YieldVault(vault1);
        YieldVault v2 = YieldVault(vault2);
        Factory f = Factory(factory);

        // Vault 1 (WETH)
        v1.setupFactoryApproval();
        v1.enableAutoMintBurn(true);
        // Have vault approve Bebop as operator on factory
        v1.execute(factory, abi.encodeWithSignature("approveOperator(address,bool)", bebop, true));
        console.log("Vault1 setup done");

        // Vault 2 (USDC)
        v2.setupFactoryApproval();
        v2.enableAutoMintBurn(true);
        v2.execute(factory, abi.encodeWithSignature("approveOperator(address,bool)", bebop, true));
        console.log("Vault2 setup done");

        vm.stopBroadcast();
    }
}
