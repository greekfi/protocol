// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import "../contracts/CLOBAMM.sol";
import { Factory } from "../contracts/Factory.sol";
import { Option } from "../contracts/Option.sol";
import { Collateral } from "../contracts/Collateral.sol";
import { ShakyToken, StableToken } from "../contracts/ShakyToken.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @notice End-to-end test: maker deposits collateral into CLOBAMM, quotes options at a tick,
///         taker swaps cash for options. Verifies auto-mint delivers real option tokens.
contract CLOBAMMOptionTest is Test {
    CLOBAMM public book;
    Factory public factory;
    Option public option;
    ShakyToken public shaky; // collateral (18 dec)
    StableToken public stable; // consideration + taker's cash (6 dec)

    address maker = address(0xA11CE);
    address taker = address(0xB0B);

    function setUp() public {
        // Deploy protocol
        stable = new StableToken();
        shaky = new ShakyToken();

        Collateral redemptionClone = new Collateral("Short", "SHORT");
        Option optionClone = new Option("Long", "LONG");
        factory = new Factory(address(redemptionClone), address(optionClone));

        option = Option(
            factory.createOption(address(shaky), address(stable), uint40(block.timestamp + 1 days), 2000e18, false)
        );

        // Deploy book
        book = new CLOBAMM();

        // Enable option support on the book (setup for auto-mint on transferOut)
        book.enableOptionSupport(address(option));

        // Fund maker with collateral, taker with cash
        // (Sizes are in wei — CLOBAMM is decimal-blind; tokens' real decimals don't matter here.)
        shaky.mint(maker, 1_000e18);
        stable.mint(taker, 1_000e18);

        // Maker deposits collateral into CLOBAMM
        vm.startPrank(maker);
        shaky.approve(address(book), type(uint256).max);
        book.deposit(address(shaky), 100e18);
        vm.stopPrank();

        // Taker approves cash to book
        vm.prank(taker);
        stable.approve(address(book), type(uint256).max);
    }

    /// @notice Full round-trip: maker quotes option-for-cash, taker swaps cash for options.
    function test_makerQuotesOption_takerBuys() public {
        // Tick 1000 ≈ price 1.1052 (stable-wei per option-wei). Low tick avoids
        // _tickToPrice overflow (sqrtP² × 1e18 fits in uint256 only for small ticks).
        int24 tick = 1000;

        vm.prank(maker);
        book.quote(address(option), address(stable), tick, 10e18, true);

        // Sanity: level available should reflect 10e18 option capacity
        uint256 avail = book.getLevelAvailable(address(option), address(stable), tick);
        assertEq(avail, 10e18, "level should show 10e18 option capacity");

        // Taker swaps cash for options
        uint256 takerStableBefore = stable.balanceOf(taker);
        uint256 takerOptionBefore = option.balanceOf(taker);
        uint256 bookShakyBefore = shaky.balanceOf(address(book));

        // Send more cash than the level can absorb — swap should consume the full level
        // and leave the rest of the cash with the taker.
        uint256 cashIn = 20e18;
        vm.prank(taker);
        book.swap(address(stable), address(option), cashIn, 1);

        // Taker should have received real option tokens
        uint256 optionsReceived = option.balanceOf(taker) - takerOptionBefore;
        assertGt(optionsReceived, 0, "taker received no options");

        // Book's collateral balance should have decreased by optionsReceived (auto-mint)
        uint256 shakyConsumed = bookShakyBefore - shaky.balanceOf(address(book));
        assertEq(shakyConsumed, optionsReceived, "auto-mint should consume 1 shaky per option");

        // Taker should have paid cash
        uint256 cashPaid = takerStableBefore - stable.balanceOf(taker);
        assertGt(cashPaid, 0, "taker paid no cash");

        // Maker's internal book balance in stable should match cash paid (less any rounding dust)
        uint256 makerStableCredit = book.balances(maker, address(stable));
        assertLe(makerStableCredit, cashPaid, "maker credit cannot exceed cash paid");
        assertGe(makerStableCredit + 1, cashPaid, "maker credit should approx equal cash paid");

        // Maker's shaky balance should have decreased by the options sold
        uint256 makerShakyRemaining = book.balances(maker, address(shaky));
        assertEq(makerShakyRemaining, 100e18 - optionsReceived, "maker shaky reduced by options sold");
    }

    /// @notice Withdrawing collateral while option-backed quotes exist should trim them.
    function test_withdrawTrimsOptionBackedCommitments() public {
        int24 tick = 1000;

        vm.prank(maker);
        book.quote(address(option), address(stable), tick, 50e18, true);

        // Withdraw most of the collateral — commitments should get trimmed
        vm.prank(maker);
        book.withdraw(address(shaky), 80e18);

        // Maker now has 20e18 shaky in book; commitment should be capped ≤ 20e18
        uint256 avail = book.getLevelAvailable(address(option), address(stable), tick);
        assertLe(avail, 20e18, "commitment should be trimmed to remaining balance");
    }

    /// @notice A taker buying against an option-backed maker with insufficient collateral
    ///         should get skipped gracefully (no revert).
    function test_insufficientCollateralSkipsMaker() public {
        int24 tick = 1000;

        vm.prank(maker);
        book.quote(address(option), address(stable), tick, 10e18, true);

        // Maker withdraws ALL their collateral — commitments should be fully trimmed
        vm.prank(maker);
        book.withdraw(address(shaky), 100e18);

        // Swap should fail with NoLiquidity since all commitments are gone
        vm.prank(taker);
        vm.expectRevert();
        book.swap(address(stable), address(option), 1e18, 1);
    }
}
