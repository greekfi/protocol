// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import "../contracts/CLOBAMM.sol";
import "../contracts/mocks/MockERC20.sol";

contract CLOBAMMTest is Test {
    CLOBAMM public book;
    MockERC20 public tokenA;
    MockERC20 public tokenB;
    MockERC20 public tokenC; // third token for cross-pair test

    address maker1 = address(0x1111);
    address maker2 = address(0x2222);
    address taker = address(0x4444);

    int24 constant TICK_A = 1000;
    int24 constant TICK_B = 2000;

    function setUp() public {
        book = new CLOBAMM();
        tokenA = new MockERC20("A", "A", 18);
        tokenB = new MockERC20("B", "B", 18);
        tokenC = new MockERC20("C", "C", 18);

        tokenA.mint(maker1, 1_000_000e18);
        tokenA.mint(taker, 1_000_000e18);
        tokenB.mint(maker1, 1000e18);
        tokenB.mint(maker2, 1000e18);
        tokenB.mint(taker, 1000e18);
        tokenC.mint(taker, 1_000_000e18);

        vm.startPrank(maker1);
        tokenA.approve(address(book), type(uint256).max);
        tokenB.approve(address(book), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(maker2);
        tokenB.approve(address(book), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(taker);
        tokenA.approve(address(book), type(uint256).max);
        tokenB.approve(address(book), type(uint256).max);
        tokenC.approve(address(book), type(uint256).max);
        vm.stopPrank();
    }

    // ============================================================
    //                     SHARED LIQUIDITY
    // ============================================================

    function test_shared_liquidity_same_pair() public {
        // Maker deposits 10 tokenB, quotes 10 at TWO different ticks
        vm.startPrank(maker1);
        book.deposit(address(tokenB), 10e18);
        book.quote(address(tokenB), address(tokenA), TICK_A, 10e18, false);
        book.quote(address(tokenB), address(tokenA), TICK_B, 10e18, false);
        vm.stopPrank();

        // Both quotes accepted — 10 WETH backs both
        assertEq(book.commitments(maker1, book.levelId(address(tokenB), address(tokenA), TICK_A)), 10e18);
        assertEq(book.commitments(maker1, book.levelId(address(tokenB), address(tokenA), TICK_B)), 10e18);

        // Taker fills 6 from tick A
        uint256 price = book.tickToPrice(TICK_A);
        vm.prank(taker);
        book.swap(address(tokenA), address(tokenB), price * 6, 0);

        // Maker balance dropped to 4
        assertEq(book.balances(maker1, address(tokenB)), 4e18);

        // Tick B still shows committed=10 but actual available is 4
        assertEq(book.commitments(maker1, book.levelId(address(tokenB), address(tokenA), TICK_B)), 10e18);
        // getLevelAvailable shows the real number
        assertEq(book.getLevelAvailable(address(tokenB), address(tokenA), TICK_B), 4e18);
    }

    function test_shared_liquidity_cross_pair() public {
        // Maker deposits 10 tokenB, quotes on two different pairs
        vm.startPrank(maker1);
        book.deposit(address(tokenB), 10e18);
        book.quote(address(tokenB), address(tokenA), TICK_A, 10e18, false); // B→A
        book.quote(address(tokenB), address(tokenC), TICK_A, 10e18, false); // B→C
        vm.stopPrank();

        // Fill 7 from B→A pair
        uint256 price = book.tickToPrice(TICK_A);
        vm.prank(taker);
        book.swap(address(tokenA), address(tokenB), price * 7, 0);

        // Balance is 3
        assertEq(book.balances(maker1, address(tokenB)), 3e18);

        // B→C pair: committed still 10, available is 3
        assertEq(book.getLevelAvailable(address(tokenB), address(tokenC), TICK_A), 3e18);

        // Taker fills B→C — gets only 3
        vm.prank(taker);
        book.swap(address(tokenC), address(tokenB), price * 10, 0);

        assertEq(book.balances(maker1, address(tokenB)), 0);
    }

    function test_withdraw_trims_commitments() public {
        vm.startPrank(maker1);
        book.deposit(address(tokenB), 10e18);
        book.quote(address(tokenB), address(tokenA), TICK_A, 10e18, false);
        book.quote(address(tokenB), address(tokenA), TICK_B, 10e18, false);

        // Withdraw 7 — remaining is 3. Both commitments should trim to 3.
        book.withdraw(address(tokenB), 7e18);

        bytes32 lidA = book.levelId(address(tokenB), address(tokenA), TICK_A);
        bytes32 lidB = book.levelId(address(tokenB), address(tokenA), TICK_B);
        assertEq(book.commitments(maker1, lidA), 3e18);
        assertEq(book.commitments(maker1, lidB), 3e18);
        assertEq(book.balances(maker1, address(tokenB)), 3e18);
        vm.stopPrank();
    }

    function test_withdraw_full_cancels_all() public {
        vm.startPrank(maker1);
        book.deposit(address(tokenB), 10e18);
        book.quote(address(tokenB), address(tokenA), TICK_A, 10e18, false);
        book.quote(address(tokenB), address(tokenA), TICK_B, 10e18, false);

        // Full withdrawal — all commitments cleared
        book.withdraw(address(tokenB), 10e18);

        bytes32 lidA = book.levelId(address(tokenB), address(tokenA), TICK_A);
        bytes32 lidB = book.levelId(address(tokenB), address(tokenA), TICK_B);
        assertEq(book.commitments(maker1, lidA), 0);
        assertEq(book.commitments(maker1, lidB), 0);
        assertEq(book.balances(maker1, address(tokenB)), 0);
        vm.stopPrank();
    }

    // ============================================================
    //                     BASIC OPS
    // ============================================================

    function test_deposit_withdraw() public {
        vm.startPrank(maker1);
        book.deposit(address(tokenB), 10e18);
        assertEq(book.balances(maker1, address(tokenB)), 10e18);
        book.withdraw(address(tokenB), 3e18);
        assertEq(book.balances(maker1, address(tokenB)), 7e18);
        vm.stopPrank();
    }

    function test_quote_and_cancel() public {
        vm.startPrank(maker1);
        book.deposit(address(tokenB), 10e18);
        book.quote(address(tokenB), address(tokenA), TICK_A, 10e18, false);

        bytes32 lid = book.levelId(address(tokenB), address(tokenA), TICK_A);
        assertEq(book.commitments(maker1, lid), 10e18);

        book.cancel(address(tokenB), address(tokenA), TICK_A);
        assertEq(book.commitments(maker1, lid), 0);
        vm.stopPrank();
    }

    function test_swap_single_maker() public {
        vm.startPrank(maker1);
        book.deposit(address(tokenB), 10e18);
        book.quote(address(tokenB), address(tokenA), TICK_A, 10e18, false);
        vm.stopPrank();

        uint256 price = book.tickToPrice(TICK_A);
        uint256 takerBBefore = tokenB.balanceOf(taker);

        vm.prank(taker);
        book.swap(address(tokenA), address(tokenB), price, 0);

        uint256 got = tokenB.balanceOf(taker) - takerBBefore;
        assertApproxEqRel(got, 1e18, 0.01e18);
    }

    function test_swap_two_makers_same_tick() public {
        vm.startPrank(maker1);
        book.deposit(address(tokenB), 6e18);
        book.quote(address(tokenB), address(tokenA), TICK_A, 6e18, false);
        vm.stopPrank();

        vm.startPrank(maker2);
        book.deposit(address(tokenB), 4e18);
        book.quote(address(tokenB), address(tokenA), TICK_A, 4e18, false);
        vm.stopPrank();

        // Taker buys 5 tokenB
        uint256 price = book.tickToPrice(TICK_A);
        vm.prank(taker);
        book.swap(address(tokenA), address(tokenB), price * 5, 0);

        // Maker1 had 6 committed, filled first (FIFO not pro-rata)
        // Maker1: 6 - 5 = 1 tokenB left
        assertEq(book.balances(maker1, address(tokenB)), 1e18);
        // Maker2 untouched
        assertEq(book.balances(maker2, address(tokenB)), 4e18);
    }

    function test_requote() public {
        vm.startPrank(maker1);
        book.deposit(address(tokenB), 10e18);
        book.quote(address(tokenB), address(tokenA), TICK_A, 10e18, false);
        book.requote(address(tokenB), address(tokenA), TICK_A, TICK_B, 10e18, false);
        vm.stopPrank();

        bytes32 lidA = book.levelId(address(tokenB), address(tokenA), TICK_A);
        bytes32 lidB = book.levelId(address(tokenB), address(tokenA), TICK_B);
        assertEq(book.commitments(maker1, lidA), 0);
        assertEq(book.commitments(maker1, lidB), 10e18);
    }

    // ============================================================
    //                     GAS BENCHMARKS
    // ============================================================

    function test_gas_quote() public {
        vm.startPrank(maker1);
        book.deposit(address(tokenB), 10e18);
        uint256 g = gasleft();
        book.quote(address(tokenB), address(tokenA), TICK_A, 10e18, false);
        emit log_named_uint("CLOB Gas: quote cold", g - gasleft());
        vm.stopPrank();
    }

    function test_gas_requote() public {
        vm.startPrank(maker1);
        book.deposit(address(tokenB), 10e18);
        book.quote(address(tokenB), address(tokenA), TICK_A, 10e18, false);

        uint256 g = gasleft();
        book.requote(address(tokenB), address(tokenA), TICK_A, TICK_B, 10e18, false);
        emit log_named_uint("CLOB Gas: requote cold", g - gasleft());
        vm.stopPrank();
    }

    function test_gas_swap() public {
        vm.startPrank(maker1);
        book.deposit(address(tokenB), 10e18);
        book.quote(address(tokenB), address(tokenA), TICK_A, 10e18, false);
        vm.stopPrank();

        uint256 price = book.tickToPrice(TICK_A);
        vm.prank(taker);
        uint256 g = gasleft();
        book.swap(address(tokenA), address(tokenB), price, 0);
        emit log_named_uint("CLOB Gas: swap 1 maker", g - gasleft());
    }

    function test_gas_cancel() public {
        vm.startPrank(maker1);
        book.deposit(address(tokenB), 10e18);
        book.quote(address(tokenB), address(tokenA), TICK_A, 10e18, false);

        uint256 g = gasleft();
        book.cancel(address(tokenB), address(tokenA), TICK_A);
        emit log_named_uint("CLOB Gas: cancel", g - gasleft());
        vm.stopPrank();
    }
}
