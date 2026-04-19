// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import "../contracts/NuAMMv2.sol";
import { Factory } from "../contracts/Factory.sol";
import { Option } from "../contracts/Option.sol";
import { Collateral } from "../contracts/Collateral.sol";
import { CreateParams } from "../contracts/interfaces/IFactory.sol";
import { ShakyToken, StableToken } from "../../contracts/mocks/ShakyToken.sol";

/// @notice End-to-end test: maker deposits collateral into NuAMMv2, quotes options at a tick,
///         taker swaps cash for options. Verifies auto-mint delivers real option tokens.
contract NuAMMv2OptionTest is Test {
    NuAMMv2 public book;
    Factory public factory;
    Option public option;
    ShakyToken public shaky;
    StableToken public stable;

    address maker = address(0xA11CE);
    address taker = address(0xB0B);

    function setUp() public {
        stable = new StableToken();
        shaky = new ShakyToken();

        Collateral redemptionClone = new Collateral("Short", "SHORT");
        Option optionClone = new Option("Long", "LONG");
        factory = new Factory(address(redemptionClone), address(optionClone));

        option = Option(
            factory.createOption(address(shaky), address(stable), uint40(block.timestamp + 1 days), 2000e18, false)
        );

        book = new NuAMMv2();
        book.enableOptionSupport(address(option));

        shaky.mint(maker, 1_000e18);
        stable.mint(taker, 1_000e18);

        vm.startPrank(maker);
        shaky.approve(address(book), type(uint256).max);
        book.deposit(address(shaky), 100e18);
        vm.stopPrank();

        vm.prank(taker);
        stable.approve(address(book), type(uint256).max);
    }

    function test_makerQuotesOption_takerBuys() public {
        int24 tick = 1000;

        vm.prank(maker);
        book.quote(address(option), address(stable), tick, 10e18, true);

        // Maker's internal collateral balance should drop by quote size (pooled into level)
        assertEq(book.balances(maker, address(shaky)), 90e18, "collateral committed into level");

        uint256 takerOptionBefore = option.balanceOf(taker);
        uint256 bookShakyBefore = shaky.balanceOf(address(book));

        uint256 cashIn = 5e18;
        vm.prank(taker);
        book.swap(address(stable), address(option), cashIn, 1);

        uint256 optionsReceived = option.balanceOf(taker) - takerOptionBefore;
        assertGt(optionsReceived, 0, "taker received no options");

        uint256 shakyConsumed = bookShakyBefore - shaky.balanceOf(address(book));
        assertEq(shakyConsumed, optionsReceived, "auto-mint should consume 1 shaky per option");
    }

    function test_cancelRefundsToCollateral() public {
        int24 tick = 1000;

        vm.prank(maker);
        book.quote(address(option), address(stable), tick, 10e18, true);
        assertEq(book.balances(maker, address(shaky)), 90e18, "committed");

        vm.prank(maker);
        book.cancel(address(option), address(stable), tick, true);

        // Full refund to collateral balance (no fills happened)
        assertEq(book.balances(maker, address(shaky)), 100e18, "refund to collateral");
    }
}
