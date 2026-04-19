// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

import { Script, console } from "forge-std/Script.sol";
import { Factory } from "../contracts/Factory.sol";
import { CLOBAMM } from "../contracts/CLOBAMM.sol";
import { ShakyToken } from "../../contracts/mocks/ShakyToken.sol";

/// @notice Post-deploy setup for the CLOB book demo.
/// @dev Creates an option, enables option-support on the book, funds a maker account.
///      Run after `yarn deploy --file DeployOp.s.sol`:
///
///      forge script script/DeployBookDemo.s.sol --broadcast \
///          --rpc-url http://localhost:8545 \
///          --account scaffold-eth-default --password localhost --legacy \
///          --sig "run(address,address,address,address)" \
///          <bookAddr> <factoryAddr> <shakyAddr> <stableAddr>
contract DeployBookDemo is Script {
    // Anvil account #1 — demo maker
    address constant MAKER = 0x70997970C51812dc3A010C7d01b50e0d17dc79C8;

    function run(address bookAddr, address factoryAddr, address shakyAddr, address stableAddr) external {
        CLOBAMM book = CLOBAMM(bookAddr);
        Factory factory = Factory(factoryAddr);
        ShakyToken shaky = ShakyToken(shakyAddr);
        ShakyToken stable = ShakyToken(stableAddr); // same interface (mintable ERC20)

        vm.startBroadcast();

        // 1. Create a spread of options (calls + puts, different expiries and strikes)
        //    Strike uses 18-decimal fixed point — for calls: cash per collateral.
        //    For puts: collateral per cash (inverse).
        address call7d_2 = factory.createOption(shakyAddr, stableAddr, uint40(block.timestamp + 7 days), 2e18, false);
        address call7d_3 = factory.createOption(shakyAddr, stableAddr, uint40(block.timestamp + 7 days), 3e18, false);
        address call30d_2 = factory.createOption(shakyAddr, stableAddr, uint40(block.timestamp + 30 days), 2e18, false);
        // Put: strike of 0.5e18 means collateral side pays out when consideration rises above 2 (1/0.5)
        address put7d_2 = factory.createOption(stableAddr, shakyAddr, uint40(block.timestamp + 7 days), 0.5e18, true);

        console.log("Call 7d @ 2:", call7d_2);
        console.log("Call 7d @ 3:", call7d_3);
        console.log("Call 30d @ 2:", call30d_2);
        console.log("Put 7d @ 2:", put7d_2);

        // 2. Enable option-support on the book for each (factory.enableAutoMintRedeem + collateral approvals)
        book.enableOptionSupport(call7d_2);
        book.enableOptionSupport(call7d_3);
        book.enableOptionSupport(call30d_2);
        book.enableOptionSupport(put7d_2);

        // 3. Fund maker with both tokens so they can deposit & post quotes / take orders
        shaky.mint(MAKER, 1000e18);
        stable.mint(MAKER, 1000e18);

        // 4. Fund the deployer as well for easy local testing
        shaky.mint(msg.sender, 1000e18);
        stable.mint(msg.sender, 1000e18);

        vm.stopBroadcast();

        console.log("=== Book Demo Setup Complete ===");
        console.log("Book:   ", bookAddr);
        console.log("Shaky:  ", shakyAddr);
        console.log("Stable: ", stableAddr);
        console.log("Maker:  ", MAKER);
    }
}
