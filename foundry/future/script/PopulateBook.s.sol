// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

import { Script, console } from "forge-std/Script.sol";
import { CLOBAMM } from "../contracts/CLOBAMM.sol";
import { ShakyToken } from "../../contracts/mocks/ShakyToken.sol";

/// @notice Populate a fresh CLOBAMM book with realistic-looking liquidity:
///         a few ask levels and a few bid levels around a ~0.17 STK/option mid.
/// @dev Run as the MAKER account (anvil account #1) after DeployBookDemo has created
///      the option and funded the maker.
///
///      forge script script/PopulateBook.s.sol --broadcast \
///          --rpc-url http://localhost:8545 --legacy \
///          --private-key 0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d \
///          --sig "run(address,address,address,address)" \
///          <bookAddr> <optionAddr> <shakyAddr> <stableAddr>
///
/// Tick cheatsheet (18dec both tokens, so tick = log-1.0001(cash-wei/option-wei) = log-1.0001(price)):
///   price  0.10 → tick -23025   price 0.30 → tick -12039
///   price  0.13 → tick -20402   price 0.25 → tick -13863
///   price  0.15 → tick -18971   price 0.22 → tick -15141
///                                price 0.20 → tick -16094
///
/// Bids (sellToken=cash, buyToken=option): tick = -ask_tick.
contract PopulateBook is Script {
    function run(address bookAddr, address optionAddr, address shakyAddr, address stableAddr) external {
        CLOBAMM book = CLOBAMM(bookAddr);

        vm.startBroadcast();

        // Approvals + deposits (maker funds both sides)
        ShakyToken(shakyAddr).approve(bookAddr, type(uint256).max);
        ShakyToken(stableAddr).approve(bookAddr, type(uint256).max);
        book.deposit(shakyAddr, 200e18);
        book.deposit(stableAddr, 50e18);

        // --- ASKS (sell options for cash): sellToken=option, buyToken=cash, isOption=true ---
        book.quote(optionAddr, stableAddr, -16094, 10e18, true); // 10 @ 0.20
        book.quote(optionAddr, stableAddr, -15141, 8e18, true); // 8  @ 0.22
        book.quote(optionAddr, stableAddr, -13863, 12e18, true); // 12 @ 0.25
        book.quote(optionAddr, stableAddr, -12039, 5e18, true); // 5  @ 0.30

        // --- BIDS (buy options with cash): sellToken=cash, buyToken=option, amount in cash-wei ---
        // Size in options × price = cash amount. e.g. 10 options × 0.15 = 1.5 cash.
        book.quote(stableAddr, optionAddr, 18971, 1_500_000_000_000_000_000, false); // 1.5 cash @ 0.15 → 10 opt
        book.quote(stableAddr, optionAddr, 20402, 1_040_000_000_000_000_000, false); // 1.04 cash @ 0.13 → 8 opt
        book.quote(stableAddr, optionAddr, 23025, 1_200_000_000_000_000_000, false); // 1.2 cash @ 0.10 → 12 opt

        vm.stopBroadcast();

        console.log("=== Book Populated ===");
        console.log("Asks: 10@0.20, 8@0.22, 12@0.25, 5@0.30 (opt->cash)");
        console.log("Bids: 10@0.15, 8@0.13, 12@0.10 (cash->opt)");
    }
}
