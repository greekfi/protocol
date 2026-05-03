// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { Test } from "forge-std/Test.sol";

import { Factory } from "../contracts/Factory.sol";
import { Receipt as Rct } from "../contracts/Receipt.sol";
import { Option } from "../contracts/Option.sol";
import { CreateParams } from "../contracts/interfaces/IFactory.sol";
import { MockERC20 } from "../contracts/mocks/MockERC20.sol";

/// @notice Factory creation validation (window defaulting, standard rules, blocklist).
contract FactoryTest is Test {
    Factory factory;
    MockERC20 coll;
    MockERC20 cons;
    uint40 EXP;

    function setUp() public {
        Rct collTpl = new Rct("C", "C");
        Option optionTpl = new Option("O", "O");
        factory = new Factory();
        coll = new MockERC20("Coll", "COLL", 18);
        cons = new MockERC20("Cons", "CONS", 18);
        EXP = uint40(block.timestamp + 7 days);
    }

    function _basicParams() internal view returns (CreateParams memory) {
        return CreateParams({
            collateral: address(coll),
            consideration: address(cons),
            expirationDate: EXP,
            strike: 1000e18,
            isPut: false,
            isEuro: false,
            windowSeconds: 0
        });
    }

    // ======== Window default + override ========

    function test_Create_DefaultsTo8hWindow() public {
        CreateParams memory p = _basicParams();
        address opt = factory.createOption(p);
        assertTrue(factory.receipts(address(Option(opt).receipt())));
        Rct c = Rct(Option(opt).receipt());
        assertEq(uint256(c.exerciseDeadline()), uint256(EXP) + 8 hours);
    }

    function test_Create_CustomWindow() public {
        CreateParams memory p = _basicParams();
        p.windowSeconds = 1 hours;
        address opt = factory.createOption(p);
        Rct c = Rct(Option(opt).receipt());
        assertEq(uint256(c.exerciseDeadline()), uint256(EXP) + 1 hours);
    }

    // ======== Standard validations ========

    function test_SameTokenReverts() public {
        CreateParams memory p = _basicParams();
        p.consideration = p.collateral;
        vm.expectRevert(Factory.InvalidTokens.selector);
        factory.createOption(p);
    }

    function test_BlocklistedCollateralReverts() public {
        factory.blockToken(address(coll));
        CreateParams memory p = _basicParams();
        vm.expectRevert(Factory.BlocklistedToken.selector);
        factory.createOption(p);
    }

    function test_ZeroStrikeReverts() public {
        CreateParams memory p = _basicParams();
        p.strike = 0;
        vm.expectRevert(Rct.InvalidValue.selector);
        factory.createOption(p);
    }

    function test_PastExpiryReverts() public {
        CreateParams memory p = _basicParams();
        p.expirationDate = uint40(block.timestamp - 1);
        vm.expectRevert(Rct.InvalidValue.selector);
        factory.createOption(p);
    }

    // ======== Backward-compat overload ========

    function test_LegacyCreateOption_DefaultsWindow() public {
        address opt = factory.createOption(
            CreateParams({
                collateral: address(coll),
                consideration: address(cons),
                expirationDate: EXP,
                strike: 1000e18,
                isPut: false,
                isEuro: false,
                windowSeconds: 0
            })
        );
        assertTrue(factory.receipts(address(Option(opt).receipt())));
        Rct c = Rct(Option(opt).receipt());
        assertEq(uint256(c.exerciseDeadline()), uint256(EXP) + 8 hours);
    }

    // ======== Blocklist ========

    function test_BlocklistWorks() public {
        factory.blockToken(address(coll));
        assertTrue(factory.isBlocked(address(coll)));
        factory.unblockToken(address(coll));
        assertFalse(factory.isBlocked(address(coll)));
    }

    function test_UnblockZeroAddressReverts() public {
        vm.expectRevert(Factory.InvalidAddress.selector);
        factory.unblockToken(address(0));
    }
}
