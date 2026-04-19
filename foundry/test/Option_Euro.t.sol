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

/// @notice European options: no exercise, oracle-settled post-expiry.
contract OptionEuroTest is Test {
    Factory factory;
    MockERC20 coll;
    MockERC20 cons;
    Option option;
    Collateral col;
    MockPriceOracle oracle;

    uint40 EXP;
    uint96 constant STRIKE = 1000e18; // consPerColl
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
            isEuro: true,
            oracleSource: address(oracle),
            twapWindow: 0
        });
        option = Option(factory.createOption(p));
        col = Collateral(option.coll());

        coll.mint(address(this), 100e18);
        coll.approve(address(factory), type(uint256).max);
        factory.approve(address(coll), type(uint256).max);

        option.mint(MINT_AMT);
    }

    // ======== Pre-expiry ========

    function test_ExerciseReverts() public {
        vm.expectRevert(Option.EuropeanExerciseDisabled.selector);
        option.exercise(1e18);
    }

    function test_PairRedeemWorks() public {
        uint256 before_ = coll.balanceOf(address(this));
        option.redeem(1e18);
        assertEq(option.balanceOf(address(this)), MINT_AMT - 1e18);
        assertEq(col.balanceOf(address(this)), MINT_AMT - 1e18);
        assertEq(coll.balanceOf(address(this)) - before_, 1e18);
    }

    function test_SettleBeforeExpiryReverts() public {
        oracle.setPrice(1500e18);
        vm.expectRevert();
        option.settle("");
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

    // ======== Settle ========

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
        option.settle(""); // no-op
        assertTrue(col.reserveInitialized());
    }

    // ======== ITM ========

    function test_ITM_ClaimAndRedeem() public {
        oracle.setPrice(2000e18); // spot > strike
        vm.warp(EXP + 1);

        uint256 collBefore = coll.balanceOf(address(this));
        option.claim(MINT_AMT);
        // option payout = amt * (S - K) / S = 10 * 1000/2000 = 5e18
        uint256 optionPayout = coll.balanceOf(address(this)) - collBefore;
        assertEq(optionPayout, 5e18);

        collBefore = coll.balanceOf(address(this));
        col.redeem(MINT_AMT);
        // coll availableColl = collBal - reserve = 5e18 - 0 = 5e18; share = 10/10 * 5 = 5e18
        uint256 collPayout = coll.balanceOf(address(this)) - collBefore;
        assertEq(collPayout, 5e18);

        // Conservation
        assertEq(optionPayout + collPayout, MINT_AMT);
        assertEq(coll.balanceOf(address(col)), 0);
    }

    function test_ITM_RedeemFirstThenClaim() public {
        oracle.setPrice(2000e18);
        vm.warp(EXP + 1);

        // Coll redeems first — reserve stays intact, so coll only gets K/S share
        uint256 collBefore = coll.balanceOf(address(this));
        col.redeem(MINT_AMT);
        uint256 collPayout = coll.balanceOf(address(this)) - collBefore;
        assertEq(collPayout, 5e18); // 10 * (10-5)/10 = 5

        // Option claims — gets the reserved 5e18
        collBefore = coll.balanceOf(address(this));
        option.claim(MINT_AMT);
        assertEq(coll.balanceOf(address(this)) - collBefore, 5e18);
        assertEq(coll.balanceOf(address(col)), 0);
    }

    function test_ITM_PartialClaim() public {
        oracle.setPrice(2000e18);
        vm.warp(EXP + 1);

        uint256 collBefore = coll.balanceOf(address(this));
        option.claim(4e18); // 4 * 1000/2000 = 2e18
        assertEq(coll.balanceOf(address(this)) - collBefore, 2e18);
        assertEq(option.balanceOf(address(this)), 6e18);

        option.claim(6e18); // 6 * 1000/2000 = 3e18
        assertEq(coll.balanceOf(address(this)) - collBefore, 5e18);
    }

    // ======== OTM ========

    function test_OTM_OptionGetsZero() public {
        oracle.setPrice(500e18); // spot < strike
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
        oracle.setPrice(uint256(STRIKE)); // spot == strike → treated as OTM
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
        oracle.setPrice(2000e18);
        vm.warp(EXP + 1);
        option.claim(MINT_AMT);
        col.redeem(MINT_AMT);
        assertEq(cons.balanceOf(address(col)), 0);
        assertEq(cons.balanceOf(address(this)), 0);
    }

    function test_NamePrefix() public view {
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

    function test_OracleAddressExposed() public view {
        assertEq(option.oracle(), address(oracle));
        assertEq(address(col.oracle()), address(oracle));
    }
}
