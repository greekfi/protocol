// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {BatchMinter} from "../src/BatchMinter.sol";
import {IOption} from "../src/interfaces/IOption.sol";
import {IOptionFactory} from "../src/interfaces/IOptionFactory.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";

contract BatchMinterTest is Test {
    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    // Valid WETH option from addresses.txt
    address constant OPTION = 0x93a8f0E3b2103F2DeeA8EcefD86701b41b7810eA;

    BatchMinter batchMinter;
    address user;

    function setUp() public {
        vm.createSelectFork("https://ethereum-rpc.publicnode.com");
        batchMinter = new BatchMinter();
        user = makeAddr("user");
        deal(WETH, user, 10 ether);
    }

    function test_batchMint() public {
        address[] memory options = new address[](1);
        options[0] = OPTION;

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 0.1 ether;

        address factory = IOption(OPTION).factory();

        vm.startPrank(user);
        IERC20(WETH).approve(factory, 0.1 ether);
        IOptionFactory(factory).approve(WETH, 0.1 ether);
        batchMinter.batchMint(options, amounts);
        vm.stopPrank();

        assertGt(IOption(OPTION).balanceOf(user), 0);
    }
}
