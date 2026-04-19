// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { Test } from "forge-std/Test.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { Factory } from "../contracts/Factory.sol";
import { Collateral } from "../contracts/Collateral.sol";
import { Option } from "../contracts/Option.sol";
import { CreateParams } from "../contracts/interfaces/IFactory.sol";
import { MockERC20 } from "../contracts/mocks/MockERC20.sol";
import { MockPriceOracle } from "./mocks/MockPriceOracle.sol";

/// @notice American + oracle settlement: exercise pre-expiry, oracle split post-expiry.
///         Verifies the pro-rata (C - optionReserve, V) math with partial exercises.
contract OptionAmericanSettledTest is Test {
    Factory factory;
    MockERC20 coll;
    MockERC20 cons;
    Option option;
    Collateral col;
    MockPriceOracle oracle;

    uint40 EXP;
    uint96 constant STRIKE = 1000e18;
    uint256 constant MINT_AMT = 10e18;

    function setUp() public {
        Collateral collTpl = new Collateral("C", "C");
        Option optionTpl = new Option("O", "O");
        factory = new Factory(address(collTpl), address(optionTpl));

        coll = new MockERC20("Collateral", "COLL", 18);
        cons = new MockERC20("Consideration", "CONS", 18);

        EXP = uint40(block.timestamp + 7 days);
        oracle = new MockPriceOracle(EXP);

        CreateParams memory p = CreateParams({
            collateral: address(coll),
            consideration: address(cons),
            expirationDate: EXP,
            strike: STRIKE,
            isPut: false,
            isEuro: false, // American — exercise works pre-expiry
            oracleSource: address(oracle),
            twapWindow: 0
        });
        option = Option(factory.createOption(p));
        col = Collateral(option.coll());

        coll.mint(address(this), 100e18);
        cons.mint(address(this), 100_000e18);
        coll.approve(address(factory), type(uint256).max);
        cons.approve(address(factory), type(uint256).max);
        factory.approve(address(coll), type(uint256).max);
        factory.approve(address(cons), type(uint256).max);

        option.mint(MINT_AMT);
    }

    // ======== Pre-expiry ========

    function test_ExerciseWorksPreExpiry() public {
        uint256 consBefore = cons.balanceOf(address(this));
        uint256 collBefore = coll.balanceOf(address(this));
        option.exercise(3e18);
        // Paid 3000e18 cons, received 3e18 coll
        assertEq(consBefore - cons.balanceOf(address(this)), 3000e18);
        assertEq(coll.balanceOf(address(this)) - collBefore, 3e18);
        // Cons now held by Collateral contract
        assertEq(cons.balanceOf(address(col)), 3000e18);
    }

    function test_PairRedeemStillWorks() public {
        uint256 collBefore = coll.balanceOf(address(this));
        option.redeem(2e18);
        assertEq(coll.balanceOf(address(this)) - collBefore, 2e18);
    }

    // ======== Settle ========

    function test_SettleAfterExpirySucceeds() public {
        oracle.setPrice(1500e18);
        vm.warp(EXP + 1);
        option.settle("");
        assertTrue(col.reserveInitialized());
    }

    function test_SettleBeforeExpiryReverts() public {
        oracle.setPrice(1500e18);
        vm.expectRevert();
        option.settle("");
    }

    // ======== ITM with partial exercise (the pro-rata stress case) ========

    /// @dev 10 minted, 3 exercised. At expiry:
    ///        O = 7, N = 10, C = 7, V = 3000e18, S = 1500, K = 1000
    ///        optionReserve = 7 * (S-K)/S = 7 * 500/1500 = 7/3 ≈ 2.3333e18
    ///        per-coll: availableColl/N = (C - reserve)/N = (7 - 7/3)/10 = 14/30 = 7/15 ≈ 0.4667e18
    ///                  consShare/N    = V/N = 3000/10 = 300e18
    function test_ITM_PartialExercise_BothSidesClaim() public {
        option.exercise(3e18);
        oracle.setPrice(1500e18);
        vm.warp(EXP + 1);

        // Option claim — payout = amount * (S-K)/S, rounded floor
        uint256 collBefore = coll.balanceOf(address(this));
        option.claim(7e18);
        uint256 optPayout = coll.balanceOf(address(this)) - collBefore;
        assertApproxEqAbs(optPayout, uint256(7e18 * 500) / 1500, 1);

        // Coll redeem — pro-rata of (C - reserve, V)
        collBefore = coll.balanceOf(address(this));
        uint256 consBefore = cons.balanceOf(address(this));
        col.redeem(10e18);
        uint256 collPayout = coll.balanceOf(address(this)) - collBefore;
        uint256 consPayout = cons.balanceOf(address(this)) - consBefore;

        // After option claim: reserve is 0, C = 7 - optPayout ≈ 4.6667e18, V = 3000e18
        assertApproxEqAbs(collPayout, 7e18 - optPayout, 1);
        assertEq(consPayout, 3000e18);

        // Conservation
        assertApproxEqAbs(optPayout + collPayout, 7e18, 2); // all remaining collateral distributed
        assertEq(consPayout, 3000e18); // all consideration distributed
    }

    /// @dev Coll redeems first — reserve stays intact, pro-rata uses (C - reserve).
    function test_ITM_PartialExercise_CollFirstThenOption() public {
        option.exercise(3e18);
        oracle.setPrice(1500e18);
        vm.warp(EXP + 1);

        uint256 collBefore = coll.balanceOf(address(this));
        uint256 consBefore = cons.balanceOf(address(this));
        col.redeem(10e18);
        uint256 collPayout = coll.balanceOf(address(this)) - collBefore;
        uint256 consPayout = cons.balanceOf(address(this)) - consBefore;

        // Reserve = 7/3 ≈ 2.333e18. Available = 7 - 7/3 = 14/3 ≈ 4.667e18.
        // All 10 coll tokens redeem → collPayout = 14/3 e18.
        assertApproxEqAbs(collPayout, uint256(14e18) / 3, 2);
        assertEq(consPayout, 3000e18);

        collBefore = coll.balanceOf(address(this));
        option.claim(7e18);
        uint256 optPayout = coll.balanceOf(address(this)) - collBefore;
        assertApproxEqAbs(optPayout, uint256(7e18 * 500) / 1500, 1);

        // Conservation
        assertApproxEqAbs(optPayout + collPayout, 7e18, 2);
    }

    // ======== OTM ========

    function test_OTM_CollGetsAllCollateral() public {
        option.exercise(3e18);
        oracle.setPrice(500e18); // S < K
        vm.warp(EXP + 1);

        option.claim(7e18);
        assertEq(coll.balanceOf(address(this)) > 0, true); // got their balance back

        uint256 collBefore = coll.balanceOf(address(this));
        uint256 consBefore = cons.balanceOf(address(this));
        col.redeem(10e18);
        // OTM: reserve = 0, coll pro-rata = full 7e18, V = 3000e18
        assertEq(coll.balanceOf(address(this)) - collBefore, 7e18);
        assertEq(cons.balanceOf(address(this)) - consBefore, 3000e18);
    }

    // ======== redeemConsideration still works ========

    function test_RedeemConsiderationStillWorks() public {
        option.exercise(3e18);
        // Even pre-expiry, redeemConsideration is available (American)
        uint256 consBefore = cons.balanceOf(address(this));
        uint256 collBalBefore = col.balanceOf(address(this));
        col.redeemConsideration(3e18);
        assertEq(cons.balanceOf(address(this)) - consBefore, 3000e18);
        assertEq(collBalBefore - col.balanceOf(address(this)), 3e18);
    }

    function test_RedeemConsideration_InsufficientConsReverts() public {
        // Before any exercise, V = 0 — redeemConsideration should revert
        vm.expectRevert(Collateral.InsufficientConsideration.selector);
        col.redeemConsideration(3e18);
    }

    // ======== Settle with no exercise ========

    function test_ITM_NoExercise_EuroLikeBehavior() public {
        // No exercise — acts like Euro
        oracle.setPrice(2000e18);
        vm.warp(EXP + 1);

        uint256 collBefore = coll.balanceOf(address(this));
        option.claim(10e18);
        // 10 * 1000/2000 = 5e18
        assertEq(coll.balanceOf(address(this)) - collBefore, 5e18);

        collBefore = coll.balanceOf(address(this));
        col.redeem(10e18);
        // C = 5, reserve = 0, all to coll
        assertEq(coll.balanceOf(address(this)) - collBefore, 5e18);
    }

    // ======== Access control ========

    function test_CreatedAsAmerican() public view {
        assertFalse(option.isEuro());
        assertEq(option.oracle(), address(oracle));
    }

    function test_NamePrefixStillOPT() public view {
        bytes memory n = bytes(option.name());
        assertEq(n[0], "O");
        assertEq(n[1], "P");
        assertEq(n[2], "T");
        assertEq(n[3], "-");
    }
}
