// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { Test } from "forge-std/Test.sol";

import { Factory } from "../contracts/Factory.sol";
import { Collateral } from "../contracts/Collateral.sol";
import { Option } from "../contracts/Option.sol";
import { CreateParams } from "../contracts/interfaces/IFactory.sol";
import { MockERC20 } from "../contracts/mocks/MockERC20.sol";
import { MockPriceOracle } from "./mocks/MockPriceOracle.sol";

/// @notice Shared setup + settle tests for oracle-settled options.
///         Concrete subclasses flip `_isEuro` to exercise the American and European paths.
abstract contract OptionSettlementBase is Test {
    Factory factory;
    MockERC20 coll;
    MockERC20 cons;
    Option option;
    Collateral col;
    MockPriceOracle oracle;

    uint40 EXP;
    uint96 constant STRIKE = 1000e18;
    uint256 constant MINT_AMT = 10e18;

    function _isEuro() internal pure virtual returns (bool);

    function setUp() public virtual {
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
            isEuro: _isEuro(),
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

    // ======== Settle (shared) ========

    function test_SettleBeforeExpiryReverts() public {
        oracle.setPrice(1500e18);
        vm.expectRevert();
        option.settle("");
    }

    function test_SettleAfterExpirySucceeds() public {
        oracle.setPrice(1500e18);
        vm.warp(EXP + 1);
        option.settle("");
        assertTrue(col.reserveInitialized());
    }

    function test_SettlePermissionless() public {
        oracle.setPrice(1500e18);
        vm.warp(EXP + 1);
        vm.prank(address(0xbeef));
        option.settle("");
        assertTrue(col.reserveInitialized());
        assertEq(col.settlementPrice(), 1500e18);
    }

    function test_SettleIdempotent() public {
        oracle.setPrice(1500e18);
        vm.warp(EXP + 1);
        option.settle("");
        option.settle("");
        assertTrue(col.reserveInitialized());
    }

    function test_OracleAddressExposed() public view {
        assertEq(option.oracle(), address(oracle));
        assertEq(address(col.oracle()), address(oracle));
    }

    function test_PairRedeem() public {
        uint256 before_ = coll.balanceOf(address(this));
        option.redeem(1e18);
        assertEq(option.balanceOf(address(this)), MINT_AMT - 1e18);
        assertEq(col.balanceOf(address(this)), MINT_AMT - 1e18);
        assertEq(coll.balanceOf(address(this)) - before_, 1e18);
    }
}

/// @notice American + oracle settlement: exercise pre-expiry, oracle split post-expiry.
///         Verifies the pro-rata (C - optionReserve, V) math with partial exercises.
contract OptionAmericanSettledTest is OptionSettlementBase {
    function _isEuro() internal pure override returns (bool) {
        return false;
    }

    // ======== Pre-expiry ========

    function test_ExerciseWorksPreExpiry() public {
        uint256 consBefore = cons.balanceOf(address(this));
        uint256 collBefore = coll.balanceOf(address(this));
        option.exercise(3e18);
        assertEq(consBefore - cons.balanceOf(address(this)), 3000e18);
        assertEq(coll.balanceOf(address(this)) - collBefore, 3e18);
        assertEq(cons.balanceOf(address(col)), 3000e18);
    }

    // ======== ITM with partial exercise (the pro-rata stress case) ========

    /// @dev 10 minted, 3 exercised. At expiry:
    ///        O = 7, N = 10, C = 7, V = 3000e18, S = 1500, K = 1000
    ///        optionReserve = 7 * (S-K)/S = 7 * 500/1500 = 7/3 ≈ 2.3333e18
    function test_ITM_PartialExercise_BothSidesClaim() public {
        option.exercise(3e18);
        oracle.setPrice(1500e18);
        vm.warp(EXP + 1);

        uint256 collBefore = coll.balanceOf(address(this));
        option.claim(7e18);
        uint256 optPayout = coll.balanceOf(address(this)) - collBefore;
        assertApproxEqAbs(optPayout, uint256(7e18 * 500) / 1500, 1);

        collBefore = coll.balanceOf(address(this));
        uint256 consBefore = cons.balanceOf(address(this));
        col.redeem(10e18);
        uint256 collPayout = coll.balanceOf(address(this)) - collBefore;
        uint256 consPayout = cons.balanceOf(address(this)) - consBefore;

        assertApproxEqAbs(collPayout, 7e18 - optPayout, 1);
        assertEq(consPayout, 3000e18);
        assertApproxEqAbs(optPayout + collPayout, 7e18, 2);
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

        assertApproxEqAbs(collPayout, uint256(14e18) / 3, 2);
        assertEq(consPayout, 3000e18);

        collBefore = coll.balanceOf(address(this));
        option.claim(7e18);
        uint256 optPayout = coll.balanceOf(address(this)) - collBefore;
        assertApproxEqAbs(optPayout, uint256(7e18 * 500) / 1500, 1);

        assertApproxEqAbs(optPayout + collPayout, 7e18, 2);
    }

    // ======== OTM ========

    function test_OTM_CollGetsAllCollateral() public {
        option.exercise(3e18);
        oracle.setPrice(500e18);
        vm.warp(EXP + 1);

        option.claim(7e18);

        uint256 collBefore = coll.balanceOf(address(this));
        uint256 consBefore = cons.balanceOf(address(this));
        col.redeem(10e18);
        assertEq(coll.balanceOf(address(this)) - collBefore, 7e18);
        assertEq(cons.balanceOf(address(this)) - consBefore, 3000e18);
    }

    // ======== redeemConsideration ========

    function test_RedeemConsiderationStillWorks() public {
        option.exercise(3e18);
        uint256 consBefore = cons.balanceOf(address(this));
        uint256 collBalBefore = col.balanceOf(address(this));
        col.redeemConsideration(3e18);
        assertEq(cons.balanceOf(address(this)) - consBefore, 3000e18);
        assertEq(collBalBefore - col.balanceOf(address(this)), 3e18);
    }

    function test_RedeemConsideration_InsufficientConsReverts() public {
        vm.expectRevert(Collateral.InsufficientConsideration.selector);
        col.redeemConsideration(3e18);
    }

    // ======== Settle with no exercise (Euro-like) ========

    function test_ITM_NoExercise_EuroLikeBehavior() public {
        oracle.setPrice(2000e18);
        vm.warp(EXP + 1);

        uint256 collBefore = coll.balanceOf(address(this));
        option.claim(10e18);
        assertEq(coll.balanceOf(address(this)) - collBefore, 5e18);

        collBefore = coll.balanceOf(address(this));
        col.redeem(10e18);
        assertEq(coll.balanceOf(address(this)) - collBefore, 5e18);
    }

    // ======== Identity ========

    function test_CreatedAsAmerican() public view {
        assertFalse(option.isEuro());
    }

    function test_NamePrefixOPT() public view {
        bytes memory n = bytes(option.name());
        assertEq(n[0], "O");
        assertEq(n[1], "P");
        assertEq(n[2], "T");
        assertEq(n[3], "-");
    }
}

/// @notice European options: exercise disabled, oracle-settled post-expiry.
contract OptionEuroTest is OptionSettlementBase {
    function _isEuro() internal pure override returns (bool) {
        return true;
    }

    // ======== Pre-expiry reverts ========

    function test_ExerciseReverts() public {
        vm.expectRevert(Option.EuropeanExerciseDisabled.selector);
        option.exercise(1e18);
    }

    function test_ClaimBeforeExpiryReverts() public {
        oracle.setPrice(1500e18);
        vm.expectRevert(Option.ContractNotExpired.selector);
        option.claim(1e18);
    }

    function test_RedeemBeforeExpiryReverts() public {
        vm.warp(EXP - 1);
        vm.expectRevert(Collateral.ContractNotExpired.selector);
        col.redeem(1e18);
    }

    // ======== ITM ========

    function test_ITM_ClaimAndRedeem() public {
        oracle.setPrice(2000e18);
        vm.warp(EXP + 1);

        uint256 collBefore = coll.balanceOf(address(this));
        option.claim(MINT_AMT);
        uint256 optionPayout = coll.balanceOf(address(this)) - collBefore;
        assertEq(optionPayout, 5e18);

        collBefore = coll.balanceOf(address(this));
        col.redeem(MINT_AMT);
        uint256 collPayout = coll.balanceOf(address(this)) - collBefore;
        assertEq(collPayout, 5e18);

        assertEq(optionPayout + collPayout, MINT_AMT);
        assertEq(coll.balanceOf(address(col)), 0);
    }

    function test_ITM_RedeemFirstThenClaim() public {
        oracle.setPrice(2000e18);
        vm.warp(EXP + 1);

        uint256 collBefore = coll.balanceOf(address(this));
        col.redeem(MINT_AMT);
        uint256 collPayout = coll.balanceOf(address(this)) - collBefore;
        assertEq(collPayout, 5e18);

        collBefore = coll.balanceOf(address(this));
        option.claim(MINT_AMT);
        assertEq(coll.balanceOf(address(this)) - collBefore, 5e18);
        assertEq(coll.balanceOf(address(col)), 0);
    }

    function test_ITM_PartialClaim() public {
        oracle.setPrice(2000e18);
        vm.warp(EXP + 1);

        uint256 collBefore = coll.balanceOf(address(this));
        option.claim(4e18);
        assertEq(coll.balanceOf(address(this)) - collBefore, 2e18);
        assertEq(option.balanceOf(address(this)), 6e18);

        option.claim(6e18);
        assertEq(coll.balanceOf(address(this)) - collBefore, 5e18);
    }

    // ======== OTM ========

    function test_OTM_OptionGetsZero() public {
        oracle.setPrice(500e18);
        vm.warp(EXP + 1);

        uint256 collBefore = coll.balanceOf(address(this));
        option.claim(MINT_AMT);
        assertEq(coll.balanceOf(address(this)), collBefore);
        assertEq(option.balanceOf(address(this)), 0);
    }

    function test_OTM_CollGetsFull() public {
        oracle.setPrice(500e18);
        vm.warp(EXP + 1);

        uint256 collBefore = coll.balanceOf(address(this));
        col.redeem(MINT_AMT);
        assertEq(coll.balanceOf(address(this)) - collBefore, MINT_AMT);
    }

    function test_OTM_AtStrikeIsOTM() public {
        oracle.setPrice(uint256(STRIKE));
        vm.warp(EXP + 1);

        uint256 collBefore = coll.balanceOf(address(this));
        option.claim(MINT_AMT);
        assertEq(coll.balanceOf(address(this)), collBefore);
    }

    // ======== Misc ========

    function test_RedeemConsiderationReverts() public {
        vm.expectRevert(Collateral.EuropeanExerciseDisabled.selector);
        col.redeemConsideration(1e18);
    }

    function test_NoConsiderationFlow() public {
        uint256 consBefore = cons.balanceOf(address(this));
        oracle.setPrice(2000e18);
        vm.warp(EXP + 1);
        option.claim(MINT_AMT);
        col.redeem(MINT_AMT);
        assertEq(cons.balanceOf(address(col)), 0);
        assertEq(cons.balanceOf(address(this)), consBefore);
    }

    function test_NamePrefixOPTE() public view {
        bytes memory n = bytes(option.name());
        assertEq(n[0], "O");
        assertEq(n[1], "P");
        assertEq(n[2], "T");
        assertEq(n[3], "E");
        assertEq(n[4], "-");
    }

    function test_IsEuroFlag() public view {
        assertTrue(option.isEuro());
        assertTrue(col.isEuro());
    }
}
