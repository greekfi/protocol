// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { Test } from "forge-std/Test.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { Factory } from "../contracts/Factory.sol";
import { Receipt as Rct } from "../contracts/Receipt.sol";
import { Option } from "../contracts/Option.sol";
import { CreateParams } from "../contracts/interfaces/IFactory.sol";
import { MockERC20 } from "../contracts/mocks/MockERC20.sol";

/// @notice Coverage for the post-expiry exercise window: pre-expiry, in-window, and post-window
///         transitions on `exercise` (long side) and `redeem` (short side).
contract ExerciseWindowTest is Test {
    Factory factory;
    MockERC20 coll;
    MockERC20 cons;
    Option option;
    Rct redemption;

    uint40 constant EXP_DELTA = 1 days;
    uint40 constant WINDOW = 1 hours;
    uint96 constant STRIKE = 1e18;

    uint160 constant MAX160 = type(uint160).max;
    uint256 constant MAX256 = type(uint256).max;

    function setUp() public {
        Rct collTpl = new Rct("C", "C");
        Option optTpl = new Option("O", "O");
        factory = new Factory(address(collTpl), address(optTpl));

        coll = new MockERC20("Coll", "COLL", 18);
        cons = new MockERC20("Cons", "CONS", 18);
        coll.mint(address(this), 1_000_000e18);
        cons.mint(address(this), 1_000_000e18);

        IERC20(address(coll)).approve(address(factory), MAX256);
        IERC20(address(cons)).approve(address(factory), MAX256);
        factory.approve(address(coll), MAX160);
        factory.approve(address(cons), MAX160);

        address opt = factory.createOption(
            CreateParams({
                collateral: address(coll),
                consideration: address(cons),
                expirationDate: uint40(block.timestamp + EXP_DELTA),
                strike: STRIKE,
                isPut: false,
                isEuro: false,
                windowSeconds: WINDOW
            })
        );
        option = Option(opt);
        redemption = Rct(option.receipt());

        option.mint(10e18);
    }

    // ============ exerciseDeadline plumbing ============

    function test_DeadlineEqualsExpirationPlusWindow() public view {
        assertEq(uint256(redemption.exerciseDeadline()), redemption.expirationDate() + WINDOW);
        assertEq(uint256(option.exerciseDeadline()), option.expirationDate() + WINDOW);
    }

    // ============ exercise transitions ============

    function test_ExercisePreExpiry_Works() public {
        option.exercise(1e18);
        assertEq(option.balanceOf(address(this)), 9e18);
    }

    function test_ExerciseInWindow_Works() public {
        // Move just past expiration but inside the window.
        vm.warp(option.expirationDate() + (WINDOW / 2));
        option.exercise(1e18);
        assertEq(option.balanceOf(address(this)), 9e18);
    }

    function test_ExerciseAfterWindow_Reverts() public {
        vm.warp(option.exerciseDeadline() + 1);
        vm.expectRevert(Option.ExerciseWindowClosed.selector);
        option.exercise(1e18);
    }

    function test_ExerciseExactlyAtDeadline_Reverts() public {
        vm.warp(option.exerciseDeadline());
        vm.expectRevert(Option.ExerciseWindowClosed.selector);
        option.exercise(1e18);
    }

    // ============ on-behalf exercise transitions ============

    function _setupKeeper() internal returns (address keeper) {
        keeper = address(0xBEEF);
        cons.mint(keeper, 100e18);
        vm.startPrank(keeper);
        IERC20(address(cons)).approve(address(factory), MAX256);
        factory.approve(address(cons), MAX160);
        vm.stopPrank();
        // Holder authorises the keeper to exercise on their behalf.
        factory.allowExercise(keeper, true);
    }

    function test_ExerciseOnBehalf_InWindow_Works() public {
        address keeper = _setupKeeper();

        vm.warp(option.expirationDate() + 1);

        vm.prank(keeper);
        option.exercise(address(this), 1e18);

        assertEq(option.balanceOf(address(this)), 9e18);
        // Keeper receives the collateral and is responsible for any owed surplus to holder.
        assertEq(coll.balanceOf(keeper), 1e18);
    }

    function test_ExerciseOnBehalf_Unauthorised_Reverts() public {
        address keeper = address(0xBEEF);
        cons.mint(keeper, 100e18);
        vm.startPrank(keeper);
        IERC20(address(cons)).approve(address(factory), MAX256);
        factory.approve(address(cons), MAX160);
        vm.stopPrank();

        vm.warp(option.expirationDate() + 1);

        vm.prank(keeper);
        vm.expectRevert(Option.ExerciseNotAllowed.selector);
        option.exercise(address(this), 1e18);
    }

    function test_ExerciseOnBehalf_RevokeWorks() public {
        address keeper = _setupKeeper();
        factory.allowExercise(keeper, false);

        vm.warp(option.expirationDate() + 1);

        vm.prank(keeper);
        vm.expectRevert(Option.ExerciseNotAllowed.selector);
        option.exercise(address(this), 1e18);
    }

    function test_ExerciseOnBehalf_OperatorAlone_Reverts() public {
        // approveOperator grants transfer authority, NOT exercise authority — exercise must still
        // be granted explicitly via allowExercise.
        address keeper = address(0xBEEF);
        cons.mint(keeper, 100e18);
        vm.startPrank(keeper);
        IERC20(address(cons)).approve(address(factory), MAX256);
        factory.approve(address(cons), MAX160);
        vm.stopPrank();
        factory.approveOperator(keeper, true);

        vm.warp(option.expirationDate() + 1);

        vm.prank(keeper);
        vm.expectRevert(Option.ExerciseNotAllowed.selector);
        option.exercise(address(this), 1e18);
    }

    function test_ExerciseOnBehalf_AfterWindow_Reverts() public {
        vm.warp(option.exerciseDeadline() + 1);
        vm.expectRevert(Option.ExerciseWindowClosed.selector);
        option.exercise(address(this), 1e18);
    }

    function test_ExerciseOnBehalf_BatchSkipsBadEntries() public {
        address keeper = _setupKeeper();

        vm.warp(option.expirationDate() + 1);

        address[] memory holders = new address[](4);
        holders[0] = address(this);
        holders[1] = address(0xDEAD);    // no balance — skipped
        holders[2] = address(0xC0FFEE);  // no allowance from this address — skipped
        holders[3] = address(this);

        uint256[] memory amounts = new uint256[](4);
        amounts[0] = 1e18;
        amounts[1] = 1e18;
        amounts[2] = 1e18;
        amounts[3] = 2e18;

        vm.prank(keeper);
        option.exercise(holders, amounts);

        // Only entries 0 and 3 burn (1e18 + 2e18); 1 lacks balance, 2 lacks allowance.
        assertEq(option.balanceOf(address(this)), 7e18);
        assertEq(coll.balanceOf(keeper), 3e18);
    }

    function test_ExerciseOnBehalf_BatchLengthMismatch_Reverts() public {
        address[] memory holders = new address[](2);
        uint256[] memory amounts = new uint256[](1);
        vm.expectRevert(Option.InvalidValue.selector);
        option.exercise(holders, amounts);
    }

    // ============ redeem (post-expiry pro-rata) transitions ============

    function test_RedeemPreExpiry_Reverts() public {
        vm.expectRevert(Rct.ExerciseWindowOpen.selector);
        redemption.redeem(1e18);
    }

    function test_RedeemDuringWindow_Reverts() public {
        vm.warp(option.expirationDate() + (WINDOW / 2));
        vm.expectRevert(Rct.ExerciseWindowOpen.selector);
        redemption.redeem(1e18);
    }

    function test_RedeemAfterWindow_Works() public {
        vm.warp(option.exerciseDeadline());
        uint256 redBalance = redemption.balanceOf(address(this));
        uint256 collBefore = coll.balanceOf(address(this));
        redemption.redeem(redBalance);
        assertEq(redemption.balanceOf(address(this)), 0);
        // Sole holder ⇒ all collateral returned.
        assertEq(coll.balanceOf(address(this)) - collBefore, redBalance);
    }

    function test_SweepBeforeWindow_Reverts() public {
        vm.expectRevert(Rct.ExerciseWindowOpen.selector);
        redemption.sweep(address(this));
    }

    function test_SweepAfterWindow_Works() public {
        vm.warp(option.exerciseDeadline() + 1);
        redemption.sweep(address(this));
        assertEq(redemption.balanceOf(address(this)), 0);
    }

    // ============ transfer follows the exercise deadline ============

    function test_Transfer_PreExpiry_Works() public {
        option.transfer(address(0xBEEF), 1e18);
        assertEq(option.balanceOf(address(0xBEEF)), 1e18);
    }

    function test_Transfer_InWindow_Works() public {
        // Inside the window, options should still circulate so holders can sell to keepers.
        vm.warp(option.expirationDate() + (WINDOW / 2));
        option.transfer(address(0xBEEF), 1e18);
        assertEq(option.balanceOf(address(0xBEEF)), 1e18);
    }

    function test_Transfer_AfterDeadline_Reverts() public {
        vm.warp(option.exerciseDeadline());
        vm.expectRevert(Option.ExerciseWindowClosed.selector);
        option.transfer(address(0xBEEF), 1e18);
    }

    // ============ pair burn follows the exercise deadline ============

    function test_PairRedeem_PreExpiry_Works() public {
        option.burn(1e18);
        assertEq(option.balanceOf(address(this)), 9e18);
        assertEq(redemption.balanceOf(address(this)), 9e18);
    }

    function test_PairRedeem_InWindow_Works() public {
        vm.warp(option.expirationDate() + (WINDOW / 2));
        option.burn(1e18);
        assertEq(option.balanceOf(address(this)), 9e18);
        assertEq(redemption.balanceOf(address(this)), 9e18);
    }

    function test_PairRedeem_AfterWindow_Reverts() public {
        // Past the deadline pair burn is closed — short side must use Receipt.redeem (pro-rata).
        vm.warp(option.exerciseDeadline() + 1 days);
        vm.expectRevert(Option.ExerciseWindowClosed.selector);
        option.burn(1e18);
    }

    // ============ European-flavour gating ============

    function _createEuro() internal returns (Option e) {
        address opt = factory.createOption(
            CreateParams({
                collateral: address(coll),
                consideration: address(cons),
                expirationDate: uint40(block.timestamp + EXP_DELTA),
                strike: STRIKE,
                isPut: false,
                isEuro: true,
                windowSeconds: WINDOW
            })
        );
        e = Option(opt);
        e.mint(10e18);
    }

    function test_European_PreExpiry_Reverts() public {
        Option euro = _createEuro();
        vm.expectRevert(Rct.EuropeanExerciseDisabled.selector);
        euro.exercise(1e18);
    }

    function test_European_InWindow_Works() public {
        Option euro = _createEuro();
        vm.warp(euro.expirationDate() + 1);
        euro.exercise(1e18);
        assertEq(euro.balanceOf(address(this)), 9e18);
    }

    function test_European_AfterWindow_Reverts() public {
        Option euro = _createEuro();
        vm.warp(euro.exerciseDeadline() + 1);
        vm.expectRevert(Option.ExerciseWindowClosed.selector);
        euro.exercise(1e18);
    }

    function test_European_ExerciseOnBehalf_PreExpiry_Reverts() public {
        Option euro = _createEuro();
        vm.expectRevert(Rct.EuropeanExerciseDisabled.selector);
        euro.exercise(address(this), 1e18);
    }

    function test_European_ReportsFlag() public {
        Option euro = _createEuro();
        assertTrue(euro.isEuro());
        // American baseline (the suite's default `option`) reports false.
        assertFalse(option.isEuro());
    }

    function test_European_NamePrefixIsRCTE() public {
        Option euro = _createEuro();
        Rct euroReceipt = Rct(euro.receipt());
        bytes memory n = bytes(euroReceipt.name());
        // Format: "RCTE-..."
        assertEq(n[0], "R");
        assertEq(n[1], "C");
        assertEq(n[2], "T");
        assertEq(n[3], "E");
        assertEq(n[4], "-");
        // And Option side uses OPTE-
        bytes memory en = bytes(euro.name());
        assertEq(en[0], "O");
        assertEq(en[1], "P");
        assertEq(en[2], "T");
        assertEq(en[3], "E");
        assertEq(en[4], "-");
    }
}
