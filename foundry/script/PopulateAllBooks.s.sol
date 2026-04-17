// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

import { Script, console } from "forge-std/Script.sol";
import { CLOBAMM } from "../contracts/CLOBAMM.sol";
import { ShakyToken } from "../contracts/ShakyToken.sol";

/// @notice Seed a realistic-looking order book on multiple options.
/// @dev Pass option addresses via a packed bytes array (abi.encodePacked).
///      Preferred: run PopulateOne for each option after DeployBookDemo.
///
///      forge script script/PopulateAllBooks.s.sol --broadcast \
///          --rpc-url http://localhost:8545 --legacy \
///          --account scaffold-eth-default --password localhost \
///          --sig "run(address,address,address,address[])" \
///          <bookAddr> <shakyAddr> <stableAddr> [optionAddrs...]
contract PopulateAllBooks is Script {
    function run(address bookAddr, address shakyAddr, address stableAddr, address[] calldata optionAddrs) external {
        CLOBAMM book = CLOBAMM(bookAddr);

        vm.startBroadcast();

        ShakyToken(shakyAddr).approve(bookAddr, type(uint256).max);
        ShakyToken(stableAddr).approve(bookAddr, type(uint256).max);

        // Single fat deposit used across all books
        book.deposit(shakyAddr, 1000e18);
        book.deposit(stableAddr, 200e18);

        for (uint256 i = 0; i < optionAddrs.length; i++) {
            address option = optionAddrs[i];
            // For calls, cash = stable (consideration). For puts, cash = shaky (collateral).
            // Cheap heuristic: we hard-code calls here. Callers should post puts manually or extend.
            // Asks: sell option for stable
            book.quote(option, stableAddr, -16094, 10e18, true); // 10 @ 0.20
            book.quote(option, stableAddr, -15141, 8e18,  true); // 8  @ 0.22
            book.quote(option, stableAddr, -13863, 12e18, true); // 12 @ 0.25
            book.quote(option, stableAddr, -12039, 5e18,  true); // 5  @ 0.30
            // Bids: sell stable for option (maker buys)
            book.quote(stableAddr, option, 18971, 1_500_000_000_000_000_000, false);
            book.quote(stableAddr, option, 20402, 1_040_000_000_000_000_000, false);
            book.quote(stableAddr, option, 23025, 1_200_000_000_000_000_000, false);
            console.log("seeded option", option);
        }

        vm.stopBroadcast();
        console.log("=== Populated", optionAddrs.length, "books ===");
    }
}
