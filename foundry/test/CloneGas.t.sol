// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { Test, console } from "forge-std/Test.sol";
import { Clones } from "@openzeppelin/contracts/proxy/Clones.sol";
import { OptionFactory, Redemption, Option, OptionParameter } from "../contracts/OptionFactory.sol";
import { ShakyToken, StableToken } from "../contracts/ShakyToken.sol";

contract CloneGas is Test {
    StableToken public stableToken;
    ShakyToken public shakyToken;
    Redemption public redemptionTemplate;
    Option public optionTemplate;
    OptionFactory public factory;

    address public constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;
    string public constant BASE_RPC_URL = "https://mainnet.base.org";

    function setUp() public {
        vm.createSelectFork(BASE_RPC_URL, 43189435);

        stableToken = new StableToken();
        shakyToken = new ShakyToken();

        redemptionTemplate = new Redemption(
            "Short Template", "SHORT", address(stableToken), address(shakyToken), block.timestamp + 1 days, 1e18, false
        );

        optionTemplate = new Option("Long Template", "LONG", address(redemptionTemplate));

        // Deploy OptionFactory
        factory = new OptionFactory(address(redemptionTemplate), address(optionTemplate), 0.0001e18);
    }

    function test_CloneGas() public {
        uint256 gasBefore = gasleft();
        address redemption_ = Clones.clone(address(redemptionTemplate));
        uint256 gasClone1 = gasBefore - gasleft();

        gasBefore = gasleft();
        address option_ = Clones.clone(address(optionTemplate));
        uint256 gasClone2 = gasBefore - gasleft();

        console.log("Clone Redemption gas:", gasClone1);
        console.log("Clone Option gas:", gasClone2);
        console.log("Total Clone gas:", gasClone1 + gasClone2);
    }
}
