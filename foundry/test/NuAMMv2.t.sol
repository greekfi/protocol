// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import "../contracts/NuAMMv2.sol";
import "../contracts/mocks/MockERC20.sol";

contract NuAMMv2Test is Test {
    NuAMMv2 public book;
    MockERC20 public tokenA; // USDC-like (buyToken)
    MockERC20 public tokenB; // WETH-like (sellToken)

    address maker1 = address(0x1111);
    address maker2 = address(0x2222);
    address taker = address(0x4444);

    // Ticks: tick 0 = price 1.0, positive ticks = higher prices
    // For "ETH at $4000": if both tokens are 18 dec, tick ≈ 82944 gives price ≈ 4000
    // For simplicity in tests, use small ticks near 0 (price ≈ 1.0)
    // tick 0 = 1.0, tick 100 = 1.01, tick 1000 = 1.105, tick 10000 = 2.718

    int24 constant TICK_A = 1000;   // price ≈ 1.1052
    int24 constant TICK_B = 2000;   // price ≈ 1.2214
    int24 constant TICK_C = 3000;   // price ≈ 1.3499

    function setUp() public {
        book = new NuAMMv2();
        tokenA = new MockERC20("TokenA", "TKA", 18);
        tokenB = new MockERC20("TokenB", "TKB", 18);

        tokenA.mint(maker1, 1_000_000e18);
        tokenA.mint(maker2, 1_000_000e18);
        tokenA.mint(taker, 1_000_000e18);
        tokenB.mint(maker1, 1000e18);
        tokenB.mint(maker2, 1000e18);
        tokenB.mint(taker, 1000e18);

        vm.startPrank(maker1);
        tokenA.approve(address(book), type(uint256).max);
        tokenB.approve(address(book), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(maker2);
        tokenA.approve(address(book), type(uint256).max);
        tokenB.approve(address(book), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(taker);
        tokenA.approve(address(book), type(uint256).max);
        tokenB.approve(address(book), type(uint256).max);
        vm.stopPrank();
    }

    // ============================================================
    //                     TICK CONVERSION
    // ============================================================

    function test_tickToPrice() public view {
        // tick 0 = price 1.0
        uint256 p0 = book.tickToPrice(0);
        assertApproxEqRel(p0, 1e18, 0.001e18); // within 0.1%

        // tick 6932 ≈ price 2.0 (ln(2)/ln(1.0001) ≈ 6931.5)
        uint256 p2 = book.tickToPrice(6932);
        assertApproxEqRel(p2, 2e18, 0.001e18);

        // negative tick = price < 1
        uint256 pHalf = book.tickToPrice(-6932);
        assertApproxEqRel(pHalf, 0.5e18, 0.001e18);
    }

    function test_priceToTick() public view {
        int24 t1 = book.priceToTick(1e18);
        assertApproxEqAbs(t1, int24(0), 1);

        int24 t2 = book.priceToTick(2e18);
        assertApproxEqAbs(t2, int24(6931), 2);

        int24 tHalf = book.priceToTick(0.5e18);
        assertApproxEqAbs(tHalf, int24(-6932), 2);
    }

    // ============================================================
    //                     CORRECTNESS
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
        assertEq(book.balances(maker1, address(tokenB)), 0);
        assertTrue(book.hasLiquidity(address(tokenB), address(tokenA), TICK_A));

        book.cancel(address(tokenB), address(tokenA), TICK_A, false);
        assertEq(book.balances(maker1, address(tokenB)), 10e18);
        assertFalse(book.hasLiquidity(address(tokenB), address(tokenA), TICK_A));
        vm.stopPrank();
    }

    function test_swap_single_level() public {
        // Maker sells 10 tokenB at tick 1000 (price ≈ 1.105 tokenA per tokenB)
        vm.startPrank(maker1);
        book.deposit(address(tokenB), 10e18);
        book.quote(address(tokenB), address(tokenA), TICK_A, 10e18, false);
        vm.stopPrank();

        uint256 price = book.tickToPrice(TICK_A);
        uint256 amountIn = price;

        uint256 takerBBefore = tokenB.balanceOf(taker);
        vm.prank(taker);
        book.swap(address(tokenA), address(tokenB), amountIn, 0);

        uint256 got = tokenB.balanceOf(taker) - takerBBefore;
        // Should get approximately 1 tokenB
        assertApproxEqRel(got, 1e18, 0.01e18); // within 1%
    }

    function test_pro_rata() public {
        // Maker1: 6 tokenB, Maker2: 4 tokenB, same tick
        vm.startPrank(maker1);
        book.deposit(address(tokenB), 6e18);
        book.quote(address(tokenB), address(tokenA), TICK_A, 6e18, false);
        vm.stopPrank();

        vm.startPrank(maker2);
        book.deposit(address(tokenB), 4e18);
        book.quote(address(tokenB), address(tokenA), TICK_A, 4e18, false);
        vm.stopPrank();

        // Taker buys 5 tokenB worth
        uint256 price = book.tickToPrice(TICK_A);

        vm.prank(taker);
        book.swap(address(tokenA), address(tokenB), price * 5, 0);

        // Settle
        address[] memory st = new address[](1);
        address[] memory bt = new address[](1);
        int24[] memory pr = new int24[](1);
        st[0] = address(tokenB);
        bt[0] = address(tokenA);
        pr[0] = TICK_A;

        book.settle(maker1, st, bt, pr);
        book.settle(maker2, st, bt, pr);

        // Maker1 had 60% shares, Maker2 had 40%
        uint256 maker1A = book.balances(maker1, address(tokenA));
        uint256 maker2A = book.balances(maker2, address(tokenA));

        // Ratio should be 60:40
        assertApproxEqRel(maker1A * 100 / (maker1A + maker2A), 60, 0.02e18);
    }

    function test_requote() public {
        vm.startPrank(maker1);
        book.deposit(address(tokenB), 10e18);
        book.quote(address(tokenB), address(tokenA), TICK_A, 10e18, false);

        book.requote(address(tokenB), address(tokenA), TICK_A, TICK_B, 10e18, false);
        vm.stopPrank();

        assertFalse(book.hasLiquidity(address(tokenB), address(tokenA), TICK_A));
        assertTrue(book.hasLiquidity(address(tokenB), address(tokenA), TICK_B));
    }

    function test_getPositions() public {
        vm.startPrank(maker1);
        book.deposit(address(tokenB), 30e18);
        book.quote(address(tokenB), address(tokenA), TICK_A, 10e18, false);
        book.quote(address(tokenB), address(tokenA), TICK_B, 10e18, false);
        book.quote(address(tokenB), address(tokenA), TICK_C, 10e18, false);

        assertEq(book.getPositionCount(maker1), 3);

        book.cancel(address(tokenB), address(tokenA), TICK_B, false);
        assertEq(book.getPositionCount(maker1), 2);

        book.cancel(address(tokenB), address(tokenA), TICK_A, false);
        book.cancel(address(tokenB), address(tokenA), TICK_C, false);
        assertEq(book.getPositionCount(maker1), 0);
        vm.stopPrank();
    }

    // ============================================================
    //                     AUTO-WALK SWAP
    // ============================================================

    function test_swap_auto_walk() public {
        // Maker quotes at 3 ticks
        vm.startPrank(maker1);
        book.deposit(address(tokenB), 30e18);
        book.quote(address(tokenB), address(tokenA), TICK_A, 10e18, false);
        book.quote(address(tokenB), address(tokenA), TICK_B, 10e18, false);
        book.quote(address(tokenB), address(tokenA), TICK_C, 10e18, false);
        vm.stopPrank();

        // Taker swaps without passing ticks — contract walks the book
        uint256 price = book.tickToPrice(TICK_A);
        uint256 takerBBefore = tokenB.balanceOf(taker);

        vm.prank(taker);
        book.swap(address(tokenA), address(tokenB), price, 0);

        // Should get ~1 tokenB at best price
        uint256 got = tokenB.balanceOf(taker) - takerBBefore;
        assertApproxEqRel(got, 1e18, 0.01e18);
    }

    function test_swap_auto_walk_sweeps_multiple_levels() public {
        vm.startPrank(maker1);
        book.deposit(address(tokenB), 3e18);
        book.quote(address(tokenB), address(tokenA), TICK_A, 1e18, false);
        book.quote(address(tokenB), address(tokenA), TICK_B, 1e18, false);
        book.quote(address(tokenB), address(tokenA), TICK_C, 1e18, false);
        vm.stopPrank();

        // Send enough to buy all 3
        uint256 bigAmount = book.tickToPrice(TICK_C) * 4;
        uint256 takerBBefore = tokenB.balanceOf(taker);

        vm.prank(taker);
        book.swap(address(tokenA), address(tokenB), bigAmount, 2e18);

        // Should get all 3 tokenB
        uint256 got = tokenB.balanceOf(taker) - takerBBefore;
        assertApproxEqRel(got, 3e18, 0.01e18);
    }

    function test_gas_swap_auto_walk() public {
        vm.startPrank(maker1);
        book.deposit(address(tokenB), 10e18);
        book.quote(address(tokenB), address(tokenA), TICK_A, 10e18, false);
        vm.stopPrank();

        uint256 price = book.tickToPrice(TICK_A);

        vm.prank(taker);
        uint256 g = gasleft();
        book.swap(address(tokenA), address(tokenB), price, 0);
        emit log_named_uint("Gas: swap auto-walk 1 level", g - gasleft());
    }

    // ============================================================
    //                     CROSSING / AUTOFILL
    // ============================================================

    function test_crossing_autofill() public {
        // Maker1 sells tokenB for tokenA at tick 1000 (price ≈ 1.105 tokenA per tokenB)
        vm.startPrank(maker1);
        book.deposit(address(tokenB), 10e18);
        book.quote(address(tokenB), address(tokenA), TICK_A, 10e18, false);
        vm.stopPrank();

        // Maker2 sells tokenA for tokenB at tick -900 (their price: 1.094 tokenB per tokenA)
        // In tokenA/tokenB terms, their bid = 1/1.094 ≈ 0.914 tokenA per tokenB
        // Maker1's ask ≈ 1.105. Bid 0.914 < ask 1.105. No cross.
        // But at tick -1100: bid = 1.0001^1100 ≈ 1.116 tokenA per tokenB. Crosses!
        int24 crossingTick = -1100;

        vm.startPrank(maker2);
        book.deposit(address(tokenA), 20e18);
        // This should auto-fill against maker1's quote
        book.quote(address(tokenA), address(tokenB), crossingTick, 5e18, false);
        vm.stopPrank();

        // Maker2 should have received some tokenB (from crossing)
        uint256 maker2B = book.balances(maker2, address(tokenB));
        assertTrue(maker2B > 0, "maker2 should have received tokenB from crossing");

        // Maker1's level should be partially filled
        uint256 maker1Remaining = book.makerBalanceAtLevel(maker1, address(tokenB), address(tokenA), TICK_A);
        assertTrue(maker1Remaining < 10e18, "maker1 level should be partially consumed");
    }

    function test_no_crossing_when_prices_dont_overlap() public {
        // Maker1 sells tokenB at tick 1000
        vm.startPrank(maker1);
        book.deposit(address(tokenB), 10e18);
        book.quote(address(tokenB), address(tokenA), TICK_A, 10e18, false);
        vm.stopPrank();

        // Maker2 sells tokenA at tick -500 (doesn't cross: -500 > -1000)
        vm.startPrank(maker2);
        book.deposit(address(tokenA), 10e18);
        book.quote(address(tokenA), address(tokenB), int24(-500), 10e18, false);
        vm.stopPrank();

        // No crossing — maker2 should have 0 tokenB
        assertEq(book.balances(maker2, address(tokenB)), 0);
        // Maker1's level untouched
        assertEq(book.makerBalanceAtLevel(maker1, address(tokenB), address(tokenA), TICK_A), 10e18);
    }

    function test_wouldCross() public {
        vm.startPrank(maker1);
        book.deposit(address(tokenB), 10e18);
        book.quote(address(tokenB), address(tokenA), TICK_A, 10e18, false);
        vm.stopPrank();

        // Would a sell of tokenA at tick -1100 cross? Yes (bestTick of B/A side is 1000, -(-1100)=1100 >= 1000)
        assertTrue(book.wouldCross(address(tokenA), address(tokenB), int24(-1100)));
        // Would tick -500 cross? No (-(-500)=500 < 1000)
        assertFalse(book.wouldCross(address(tokenA), address(tokenB), int24(-500)));
    }

    function test_getBestTick() public {
        vm.startPrank(maker1);
        book.deposit(address(tokenB), 30e18);
        book.quote(address(tokenB), address(tokenA), TICK_B, 10e18, false);
        book.quote(address(tokenB), address(tokenA), TICK_A, 10e18, false); // lower tick = better ask

        (int24 best, bool active) = book.getBestTick(address(tokenB), address(tokenA));
        assertTrue(active);
        assertEq(best, TICK_A); // 1000 < 2000

        book.cancel(address(tokenB), address(tokenA), TICK_A, false);
        (best, active) = book.getBestTick(address(tokenB), address(tokenA));
        // TICK_B is in a different bitmap word — pair goes inactive until next quote
        assertFalse(active);

        // A new quote re-establishes bestTick from the new tick
        book.quote(address(tokenB), address(tokenA), TICK_C, 10e18, false);
        (best, active) = book.getBestTick(address(tokenB), address(tokenA));
        assertTrue(active);
        assertEq(best, TICK_C); // only knows about TICK_C — TICK_B is "forgotten"

        // But TICK_B still has liquidity and works for swaps
        assertTrue(book.hasLiquidity(address(tokenB), address(tokenA), TICK_B));
        vm.stopPrank();
    }

    // ============================================================
    //                     GAS BENCHMARKS
    // ============================================================

    function test_gas_requote_cold() public {
        vm.startPrank(maker1);
        book.deposit(address(tokenB), 10e18);
        book.quote(address(tokenB), address(tokenA), TICK_A, 10e18, false);

        uint256 g = gasleft();
        book.requote(address(tokenB), address(tokenA), TICK_A, TICK_B, 10e18, false);
        emit log_named_uint("Gas: requote cold", g - gasleft());
        vm.stopPrank();
    }

    function test_gas_requote_warm() public {
        vm.startPrank(maker1);
        book.deposit(address(tokenB), 10e18);
        book.quote(address(tokenB), address(tokenA), TICK_A, 10e18, false);
        book.requote(address(tokenB), address(tokenA), TICK_A, TICK_B, 10e18, false);
        book.requote(address(tokenB), address(tokenA), TICK_B, TICK_A, 10e18, false);

        uint256 g = gasleft();
        book.requote(address(tokenB), address(tokenA), TICK_A, TICK_B, 10e18, false);
        emit log_named_uint("Gas: requote warm", g - gasleft());
        vm.stopPrank();
    }

    function test_gas_breakdown() public {
        vm.startPrank(maker1);
        book.deposit(address(tokenB), 10e18);
        // Warm up both ticks
        book.quote(address(tokenB), address(tokenA), TICK_A, 10e18, false);
        book.requote(address(tokenB), address(tokenA), TICK_A, TICK_B, 10e18, false);
        book.requote(address(tokenB), address(tokenA), TICK_B, TICK_A, 10e18, false);

        // Now measure the pieces individually on warm storage

        // 1. Cancel only
        uint256 g = gasleft();
        book.cancel(address(tokenB), address(tokenA), TICK_A, false);
        emit log_named_uint("  cancel alone", g - gasleft());

        // 2. Quote only (into warm level)
        g = gasleft();
        book.quote(address(tokenB), address(tokenA), TICK_A, 10e18, false);
        emit log_named_uint("  quote alone (warm level)", g - gasleft());

        // 3. Cancel again
        book.cancel(address(tokenB), address(tokenA), TICK_A, false);

        // 4. Quote into cold level (never used tick)
        g = gasleft();
        book.quote(address(tokenB), address(tokenA), int24(5000), 10e18, false);
        emit log_named_uint("  quote alone (cold level)", g - gasleft());

        book.cancel(address(tokenB), address(tokenA), int24(5000), false);

        // 5. Requote warm (combined)
        book.quote(address(tokenB), address(tokenA), TICK_A, 10e18, false);
        g = gasleft();
        book.requote(address(tokenB), address(tokenA), TICK_A, TICK_B, 10e18, false);
        emit log_named_uint("  requote warm (combined)", g - gasleft());

        vm.stopPrank();
    }

    function test_gas_swap_1_level() public {
        vm.startPrank(maker1);
        book.deposit(address(tokenB), 10e18);
        book.quote(address(tokenB), address(tokenA), TICK_A, 10e18, false);
        vm.stopPrank();

        uint256 price = book.tickToPrice(TICK_A);

        vm.prank(taker);
        uint256 g = gasleft();
        book.swap(address(tokenA), address(tokenB), price, 0);
        emit log_named_uint("Gas: swap 1 level", g - gasleft());
    }

    function test_gas_swap_3_levels() public {
        vm.startPrank(maker1);
        book.deposit(address(tokenB), 30e18);
        book.quote(address(tokenB), address(tokenA), TICK_A, 10e18, false);
        book.quote(address(tokenB), address(tokenA), TICK_B, 10e18, false);
        book.quote(address(tokenB), address(tokenA), TICK_C, 10e18, false);
        vm.stopPrank();

        uint256 priceC = book.tickToPrice(TICK_C);

        vm.prank(taker);
        uint256 g = gasleft();
        book.swap(address(tokenA), address(tokenB), priceC * 25, 0);
        emit log_named_uint("Gas: swap 3 levels", g - gasleft());
    }

    function test_gas_bounce_10_ticks() public {
        int24[10] memory tickLadder = [
            int24(900), int24(920), int24(940), int24(960), int24(980),
            int24(1000), int24(1020), int24(1040), int24(1060), int24(1080)
        ];

        vm.startPrank(maker1);
        book.deposit(address(tokenB), 10e18);

        // Warm up all 10 ticks
        for (uint256 i = 0; i < 10; i++) {
            book.quote(address(tokenB), address(tokenA), tickLadder[i], 10e18, false);
            book.cancel(address(tokenB), address(tokenA), tickLadder[i], false);
        }

        // Bounce 50 times using requote
        uint256 totalGas;
        uint256 minGas = type(uint256).max;
        uint256 maxGas = 0;

        book.quote(address(tokenB), address(tokenA), tickLadder[0], 10e18, false);

        for (uint256 i = 1; i < 50; i++) {
            int24 fromTick = tickLadder[(i - 1) % 10];
            int24 toTick = tickLadder[i % 10];

            uint256 gasBefore = gasleft();
            book.requote(address(tokenB), address(tokenA), fromTick, toTick, 10e18, false);
            uint256 gasUsed = gasBefore - gasleft();

            totalGas += gasUsed;
            if (gasUsed < minGas) minGas = gasUsed;
            if (gasUsed > maxGas) maxGas = gasUsed;
        }

        emit log_named_uint("Bounce 10 ticks x50 - MIN", minGas);
        emit log_named_uint("Bounce 10 ticks x50 - MAX", maxGas);
        emit log_named_uint("Bounce 10 ticks x50 - AVG", totalGas / 49);

        vm.stopPrank();
    }

    function test_gas_granular() public {
        vm.startPrank(maker1);
        book.deposit(address(tokenB), 100e18);
        
        // Warm up tick A and B fully
        book.quote(address(tokenB), address(tokenA), TICK_A, 10e18, false);
        book.requote(address(tokenB), address(tokenA), TICK_A, TICK_B, 10e18, false);
        book.requote(address(tokenB), address(tokenA), TICK_B, TICK_A, 10e18, false);
        book.cancel(address(tokenB), address(tokenA), TICK_A, false);
        
        // Now everything is warm. Measure quote in isolation.
        uint256 g = gasleft();
        book.quote(address(tokenB), address(tokenA), TICK_A, 10e18, false);
        emit log_named_uint("quote into warm (existing array slot)", g - gasleft());
        
        g = gasleft();
        book.cancel(address(tokenB), address(tokenA), TICK_A, false);
        emit log_named_uint("cancel warm", g - gasleft());
        
        // Quote into tick B — array slot should be warm from earlier use
        g = gasleft();
        book.quote(address(tokenB), address(tokenA), TICK_B, 10e18, false);
        emit log_named_uint("quote into warm B (reuse array slot)", g - gasleft());

        book.cancel(address(tokenB), address(tokenA), TICK_B, false);

        // Quote into a never-used tick — truly cold array slot
        g = gasleft();
        book.quote(address(tokenB), address(tokenA), int24(9999), 10e18, false);
        emit log_named_uint("quote into cold (new array slot)", g - gasleft());

        book.cancel(address(tokenB), address(tokenA), int24(9999), false);
        
        vm.stopPrank();
    }
}
