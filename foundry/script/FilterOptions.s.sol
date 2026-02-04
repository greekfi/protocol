// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { Script, console } from "forge-std/Script.sol";
import { IOption } from "../contracts/interfaces/IOption.sol";

contract FilterOptions is Script {
    address constant WETH_MAINNET = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant USDC_MAINNET = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    function run() external view {
        // COLLATERAL: "WETH" or "USDC"
        // TYPE: "CALL" or "PUT" (optional, defaults to any)
        string memory collateralName = vm.envOr("COLLATERAL", string("WETH"));
        string memory optionType = vm.envOr("TYPE", string("ANY"));

        address collateral;
        if (keccak256(bytes(collateralName)) == keccak256("USDC")) {
            collateral = USDC_MAINNET;
        } else {
            collateral = WETH_MAINNET;
        }

        bool filterPut = keccak256(bytes(optionType)) == keccak256("PUT");
        bool filterCall = keccak256(bytes(optionType)) == keccak256("CALL");

        string memory addressesFile = vm.readFile("addresses.txt");
        string[] memory lines = vm.split(addressesFile, "\n");

        console.log("=== Filtering Option Tokens ===");
        console.log("Collateral:", collateralName);
        console.log("Type filter:", optionType);
        console.log("");

        uint256 validCount = 0;

        for (uint256 i = 0; i < lines.length; i++) {
            string memory line = lines[i];
            if (bytes(line).length == 0) continue;

            address tokenAddr = vm.parseAddress(line);

            try IOption(tokenAddr).name() returns (string memory tokenName) {
                if (!_startsWith(tokenName, "OPT-")) continue;

                if (IOption(tokenAddr).collateral() != collateral) continue;
                if (IOption(tokenAddr).expirationDate() <= block.timestamp) continue;

                bool isPut = IOption(tokenAddr).isPut();

                if (filterPut && !isPut) continue;
                if (filterCall && isPut) continue;

                validCount++;
                console.log("VALID:", vm.toString(tokenAddr));
                console.log("  Name:", tokenName);
                console.log("  isPut:", isPut);
                console.log("");
            } catch {
                continue;
            }
        }

        console.log("=== Summary ===");
        console.log("Valid:", validCount);
    }

    function _startsWith(string memory str, string memory prefix) internal pure returns (bool) {
        bytes memory strBytes = bytes(str);
        bytes memory prefixBytes = bytes(prefix);
        if (strBytes.length < prefixBytes.length) return false;
        for (uint256 i = 0; i < prefixBytes.length; i++) {
            if (strBytes[i] != prefixBytes[i]) return false;
        }
        return true;
    }
}
