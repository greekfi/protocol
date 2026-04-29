// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { Test } from "forge-std/Test.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { Factory } from "../contracts/Factory.sol";
import { Collateral } from "../contracts/Collateral.sol";
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
    Collateral redemption;

    uint40 constant EXP_DELTA = 1 days;
    uint40 constant WINDOW = 1 hours;
    uint96 constant STRIKE = 1e18;

    uint160 constant MAX160 = type(uint160).max;
    uint256 constant MAX256 = type(uint256).max;

    function setUp() public {
        Collateral collTpl = new Collateral("C", "C");
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
                windowSeconds: WINDOW
            })
        );
        option = Option(opt);
        redemption = Collateral(option.coll());

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

    // ============ exerciseFor transitions ============

    function test_ExerciseFor_InWindow_Works() public {
        // Holder cannot consume own option here — keeper does it.
        address keeper = address(0xBEEF);
        cons.mint(keeper, 100e18);
        vm.startPrank(keeper);
        IERC20(address(cons)).approve(address(factory), MAX256);
        factory.approve(address(cons), MAX160);
        vm.stopPrank();

        vm.warp(option.expirationDate() + 1);

        vm.prank(keeper);
        option.exerciseFor(address(this), 1e18, keeper);

        assertEq(option.balanceOf(address(this)), 9e18);
        assertEq(coll.balanceOf(keeper), 1e18);
    }

    function test_ExerciseFor_AfterWindow_Reverts() public {
        vm.warp(option.exerciseDeadline() + 1);
        vm.expectRevert(Option.ExerciseWindowClosed.selector);
        option.exerciseFor(address(this), 1e18, address(this));
    }

    function test_ExerciseFor_BatchSkipsBadEntries() public {
        address keeper = address(0xBEEF);
        cons.mint(keeper, 100e18);
        vm.startPrank(keeper);
        IERC20(address(cons)).approve(address(factory), MAX256);
        factory.approve(address(cons), MAX160);
        vm.stopPrank();

        vm.warp(option.expirationDate() + 1);

        address[] memory holders = new address[](3);
        holders[0] = address(this);
        holders[1] = address(0xDEAD); // no balance — should be skipped
        holders[2] = address(this);

        uint256[] memory amounts = new uint256[](3);
        amounts[0] = 1e18;
        amounts[1] = 1e18;
        amounts[2] = 2e18;

        vm.prank(keeper);
        option.exerciseFor(holders, amounts, keeper);

        // 1e18 + 2e18 burned from this; the 0xDEAD entry skipped.
        assertEq(option.balanceOf(address(this)), 7e18);
        assertEq(coll.balanceOf(keeper), 3e18);
    }

    function test_ExerciseFor_BatchLengthMismatch_Reverts() public {
        address[] memory holders = new address[](2);
        uint256[] memory amounts = new uint256[](1);
        vm.expectRevert(Option.InvalidValue.selector);
        option.exerciseFor(holders, amounts, address(this));
    }

    // ============ redeem (post-expiry pro-rata) transitions ============

    function test_RedeemPreExpiry_Reverts() public {
        vm.expectRevert(Collateral.ExerciseWindowOpen.selector);
        redemption.redeem(1e18);
    }

    function test_RedeemDuringWindow_Reverts() public {
        vm.warp(option.expirationDate() + (WINDOW / 2));
        vm.expectRevert(Collateral.ExerciseWindowOpen.selector);
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
        vm.expectRevert(Collateral.ExerciseWindowOpen.selector);
        redemption.sweep(address(this));
    }

    function test_SweepAfterWindow_Works() public {
        vm.warp(option.exerciseDeadline() + 1);
        redemption.sweep(address(this));
        assertEq(redemption.balanceOf(address(this)), 0);
    }

    // ============ pair redeem stays valid the entire lifetime ============

    function test_PairRedeem_PreExpiry_Works() public {
        option.redeem(1e18);
        assertEq(option.balanceOf(address(this)), 9e18);
        assertEq(redemption.balanceOf(address(this)), 9e18);
    }

    function test_PairRedeem_InWindow_Works() public {
        vm.warp(option.expirationDate() + (WINDOW / 2));
        option.redeem(1e18);
        assertEq(option.balanceOf(address(this)), 9e18);
        assertEq(redemption.balanceOf(address(this)), 9e18);
    }

    function test_PairRedeem_AfterWindow_Works() public {
        vm.warp(option.exerciseDeadline() + 1 days);
        option.redeem(1e18);
        assertEq(option.balanceOf(address(this)), 9e18);
        assertEq(redemption.balanceOf(address(this)), 9e18);
    }
}
