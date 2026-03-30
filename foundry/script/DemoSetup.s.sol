// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

import { Script, console } from "forge-std/Script.sol";
import { OptionFactory } from "../contracts/OptionFactory.sol";
import { YieldVault } from "../contracts/YieldVault.sol";
import { ShakyToken } from "../contracts/ShakyToken.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @notice Post-deploy setup: create option, configure vault, fund accounts
/// @dev Run after `yarn deploy` on a forked chain with BebopSettlement
///      forge script script/DemoSetup.s.sol --broadcast --rpc-url http://localhost:8545 --account scaffold-eth-default --password localhost --legacy
contract DemoSetup is Script {
    address constant BEBOP = 0xbbbbbBB520d69a9775E85b458C58c648259FAD5F;

    // Anvil account #1 = maker (buys options, pays premium)
    address constant MAKER = 0x70997970C51812dc3A010C7d01b50e0d17dc79C8;
    uint256 constant MAKER_PK = 0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d;

    function run(
        address factoryAddr,
        address vaultAddr,
        address shakyAddr,
        address stableAddr,
        address operator
    ) external {
        OptionFactory factory = OptionFactory(factoryAddr);
        YieldVault vault = YieldVault(vaultAddr);
        ShakyToken shaky = ShakyToken(shakyAddr);

        // --- Owner broadcast (deployer = vault owner) ---
        vm.startBroadcast();

        // 1. Create options: shaky collateral, stable consideration, different expiries
        address option1 = factory.createOption(shakyAddr, stableAddr, uint40(block.timestamp + 7 days), 1e18, true);
        address option2 = factory.createOption(shakyAddr, stableAddr, uint40(block.timestamp + 30 days), 1e18, true);
        console.log("Option 7d:", option1);
        console.log("Option 30d:", option2);

        // 2. Configure vault
        vault.setupFactoryApproval();
        vault.enableAutoMintRedeem(true);
        vault.addOption(option1, BEBOP);
        vault.addOption(option2, BEBOP);
        vault.approveToken(address(shaky), BEBOP, type(uint256).max);

        // Factory internal approval (vault needs factory.approve so auto-mint can pull collateral)
        vault.execute(address(factory), abi.encodeWithSignature("approve(address,uint256)", address(shaky), type(uint256).max));

        // 3. Set operator
        if (operator != address(0)) {
            vault.setOperator(operator, true);
            console.log("Operator set:", operator);
        }

        // 4. Fund accounts
        shaky.mint(msg.sender, 1000e18); // owner/LP
        shaky.mint(MAKER, 100e18);
        shaky.mint(operator, 1000e18);

        // 5. Send gas to operator
        if (operator != address(0) && operator.balance < 1 ether) {
            payable(operator).transfer(10 ether);
        }

        vm.stopBroadcast();

        // --- Maker broadcast ---
        vm.startBroadcast(MAKER_PK);
        shaky.approve(BEBOP, type(uint256).max);
        vm.stopBroadcast();

        console.log("=== Demo Setup Complete ===");
        console.log("Option 7d:", option1);
        console.log("Option 30d:", option2);
        console.log("Maker:", MAKER);
        console.log("BEBOP:", BEBOP);
    }
}
