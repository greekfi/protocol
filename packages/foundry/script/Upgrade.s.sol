// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { Script, console } from "forge-std/Script.sol";
import { OptionFactory } from "../contracts/OptionFactory.sol";

/**
 * @title Upgrade
 * @notice Script for upgrading the OptionFactory implementation to a new version
 * @dev This script demonstrates how to upgrade the factory to a new implementation.
 *      Before running this script:
 *      1. Update the PROXY_ADDRESS constant with your deployed proxy address
 *      2. Deploy a new implementation contract (OptionFactoryV2)
 *      3. Ensure you're using the deployer account that owns the factory
 *
 * Usage:
 *   forge script script/Upgrade.s.sol:Upgrade --rpc-url <network> --broadcast --verify
 */
contract Upgrade is Script {
    // ============ CONFIGURATION ============

    /// @notice Address of the existing proxy contract
    /// @dev UPDATE THIS with your deployed proxy address before running
    address constant PROXY_ADDRESS = address(0); // TODO: Set this to your proxy address

    // ============ UPGRADE FUNCTION ============

    function run() external {
        require(PROXY_ADDRESS != address(0), "Must set PROXY_ADDRESS");

        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        // Deploy new implementation (e.g., OptionFactoryV2)
        // For this example, we're just deploying the same OptionFactory
        // In a real upgrade, you would deploy your new version here
        OptionFactory newImplementation = new OptionFactory();

        console.log("New Implementation deployed at:", address(newImplementation));

        // Get the factory through the proxy
        OptionFactory factory = OptionFactory(PROXY_ADDRESS);

        console.log("Upgrading proxy at:", PROXY_ADDRESS);
        console.log("Current owner:", factory.owner());

        // Upgrade to new implementation
        // Note: This calls upgradeToAndCall with empty data
        // If your new implementation needs initialization, pass the data as second argument
        factory.upgradeToAndCall(address(newImplementation), "");

        console.log("Upgrade complete!");
        console.log("Proxy now points to:", address(newImplementation));

        // Verify storage was preserved
        console.log("Factory fee (should be unchanged):", factory.fee());
        console.log("Redemption template (should be unchanged):", factory.redemptionClone());
        console.log("Option template (should be unchanged):", factory.optionClone());

        vm.stopBroadcast();
    }
}

/**
 * @title UpgradeLocal
 * @notice Script for upgrading on local Anvil network (uses vm.addr for private key)
 * @dev Simpler version for testing upgrades locally without private key management
 */
contract UpgradeLocal is Script {
    address constant PROXY_ADDRESS = address(0); // Set this to your local proxy address

    function run() external {
        require(PROXY_ADDRESS != address(0), "Must set PROXY_ADDRESS");

        // Use default Anvil account (account 0)
        vm.startBroadcast();

        OptionFactory newImplementation = new OptionFactory();
        console.log("New Implementation deployed at:", address(newImplementation));

        OptionFactory factory = OptionFactory(PROXY_ADDRESS);
        console.log("Upgrading proxy at:", PROXY_ADDRESS);

        factory.upgradeToAndCall(address(newImplementation), "");

        console.log("Upgrade complete!");
        console.log("Storage preserved - fee:", factory.fee());

        vm.stopBroadcast();
    }
}
