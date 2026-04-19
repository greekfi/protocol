// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

import { Script, console } from "forge-std/Script.sol";
import { CLOBAMM } from "../contracts/CLOBAMM.sol";
import { ShakyToken } from "../contracts/ShakyToken.sol";

/// @notice Seed each option with a DIFFERENT order book so switching options is visibly different.
/// @dev Re-runnable: cancels the uniform ticks posted by PopulateAllBooks first.
///
///      forge script script/PopulateVariedBooks.s.sol --broadcast \
///          --rpc-url http://localhost:8545 --legacy \
///          --account scaffold-eth-default --password localhost \
///          --sig "run(address,address,address,address,address,address,address,address)" \
///          <book> <shaky> <stable> <call1> <call2> <call3> <call30d> <put>
///
/// Tick cheatsheet (tick = log-1.0001 of price, 18/18 decimals):
///     price  tick          price  tick
///     0.03   -35066        0.20   -16094
///     0.04   -32189        0.21   -15607
///     0.05   -29957        0.22   -15141
///     0.06   -28134        0.24   -14265
///     0.07   -26593        0.25   -13863
///     0.08   -25257        0.26   -13471
///     0.09   -24079        0.28   -12725
///     0.10   -23025        0.30   -12039
///     0.11   -22072        0.32   -11393
///     0.12   -21202        0.35   -10498
///     0.13   -20402        0.40   -9162
///     0.14   -19660        0.45   -7985
///     0.15   -18971        0.50   -6932
///     0.16   -18325
///     0.17   -17716
///     0.18   -17147
///     0.19   -16606
///
/// Bid side tick = -ask tick (sellToken/buyToken flipped).
contract PopulateVariedBooks is Script {
    int24[4] TICK_OLD_ASK = [int24(-16094), int24(-15141), int24(-13863), int24(-12039)];
    int24[3] TICK_OLD_BID = [int24(18971), int24(20402), int24(23025)];

    function run(
        address book_,
        address shaky,
        address stable,
        address call1,
        address call2,
        address call3,
        address call30d,
        address put
    ) external {
        CLOBAMM book = CLOBAMM(book_);

        vm.startBroadcast();

        // Top up balances (no-op if already deposited by earlier scripts — these are fresh amounts)
        ShakyToken(shaky).approve(book_, type(uint256).max);
        ShakyToken(stable).approve(book_, type(uint256).max);
        book.deposit(shaky, 500e18);
        book.deposit(stable, 500e18);

        // --- Clear uniform quotes left by PopulateAllBooks ---
        address[4] memory calls = [call1, call2, call3, call30d];
        for (uint256 i = 0; i < calls.length; i++) {
            for (uint256 j = 0; j < TICK_OLD_ASK.length; j++) {
                book.cancel(calls[i], stable, TICK_OLD_ASK[j]);
            }
            for (uint256 j = 0; j < TICK_OLD_BID.length; j++) {
                book.cancel(stable, calls[i], TICK_OLD_BID[j]);
            }
        }

        // =========================
        // call1: ATM-ish, tight spread, moderate depth
        // mid ~ 0.175
        // =========================
        _ask(book, call1, stable, -17147, 5e18); // 5 @ 0.18
        _ask(book, call1, stable, -16606, 10e18); // 10 @ 0.19
        _ask(book, call1, stable, -15607, 8e18); // 8  @ 0.21
        _ask(book, call1, stable, -13863, 15e18); // 15 @ 0.25
        _bid(book, call1, stable, 18325, 8e18, 0.16e18); // 8  @ 0.16
        _bid(book, call1, stable, 19660, 14e18, 0.14e18); // 14 @ 0.14
        _bid(book, call1, stable, 22072, 20e18, 0.11e18); // 20 @ 0.11
        console.log("call1 seeded");

        // =========================
        // call2: similar strike, different distribution (fatter depth at worse levels)
        // mid ~ 0.21
        // =========================
        _ask(book, call2, stable, -16094, 20e18); // 20 @ 0.20
        _ask(book, call2, stable, -15141, 6e18); // 6  @ 0.22
        _ask(book, call2, stable, -13471, 10e18); // 10 @ 0.26
        _ask(book, call2, stable, -11393, 4e18); // 4  @ 0.32
        _bid(book, call2, stable, 17147, 10e18, 0.18e18); // 10 @ 0.18
        _bid(book, call2, stable, 18971, 15e18, 0.15e18); // 15 @ 0.15
        _bid(book, call2, stable, 21202, 22e18, 0.12e18); // 22 @ 0.12
        _bid(book, call2, stable, 24079, 8e18, 0.09e18); // 8  @ 0.09
        console.log("call2 seeded");

        // =========================
        // call3: strike 3 = OTM, cheaper premium, thinner book
        // mid ~ 0.075
        // =========================
        _ask(book, call3, stable, -26593, 12e18); // 12 @ 0.07
        _ask(book, call3, stable, -25257, 8e18); // 8  @ 0.08
        _ask(book, call3, stable, -23025, 5e18); // 5  @ 0.10
        _ask(book, call3, stable, -19660, 3e18); // 3  @ 0.14
        _bid(book, call3, stable, 29957, 10e18, 0.05e18); // 10 @ 0.05
        _bid(book, call3, stable, 32189, 7e18, 0.04e18); // 7  @ 0.04
        _bid(book, call3, stable, 35066, 5e18, 0.03e18); // 5  @ 0.03
        console.log("call3 seeded");

        // =========================
        // call30d: 30-day, richer premium (time value)
        // mid ~ 0.33
        // =========================
        _ask(book, call30d, stable, -10498, 8e18); // 8  @ 0.35
        _ask(book, call30d, stable, -9162, 12e18); // 12 @ 0.40
        _ask(book, call30d, stable, -7985, 6e18); // 6  @ 0.45
        _bid(book, call30d, stable, 11393, 10e18, 0.32e18); // 10 @ 0.32
        _bid(book, call30d, stable, 13471, 15e18, 0.26e18); // 15 @ 0.26
        _bid(book, call30d, stable, 16094, 8e18, 0.2e18); // 8  @ 0.20
        console.log("call30d seeded");

        // =========================
        // put: cash side is STABLE for this put (collateral = stable).
        // Premium quoted in stable per put. Skinny book.
        // mid ~ 0.09 stable per put
        // =========================
        _ask(book, put, stable, -25257, 5e18); // 5  @ 0.08
        _ask(book, put, stable, -23025, 10e18); // 10 @ 0.10
        _ask(book, put, stable, -19660, 4e18); // 4  @ 0.14
        _bid(book, put, stable, 28134, 5e18, 0.06e18); // 5  @ 0.06
        _bid(book, put, stable, 32189, 8e18, 0.04e18); // 8  @ 0.04
        console.log("put seeded");

        vm.stopBroadcast();
        console.log("=== Varied books posted ===");
    }

    // --- helpers ---

    function _ask(CLOBAMM book, address option, address cash, int24 tick, uint256 amount) internal {
        book.quote(option, cash, tick, amount, true);
    }

    /// @dev amountOptions × pricePerOption = cashAmount (all 18-dec).
    function _bid(CLOBAMM book, address option, address cash, int24 tick, uint256 amountOptions, uint256 priceWad)
        internal
    {
        uint256 cashAmount = (amountOptions * priceWad) / 1e18;
        book.quote(cash, option, tick, cashAmount, false);
    }
}
