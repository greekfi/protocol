// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { Test, console } from "forge-std/Test.sol";
import { Clones } from "@openzeppelin/contracts/proxy/Clones.sol";
import { Factory } from "../contracts/Factory.sol";
import { Collateral } from "../contracts/Collateral.sol";
import { Option } from "../contracts/Option.sol";
import { ShakyToken, StableToken } from "../contracts/ShakyToken.sol";

contract CloneGas is Test {
    StableToken public stableToken;
    ShakyToken public shakyToken;
    Collateral public collTemplate;
    Option public optionTemplate;
    Factory public factory;

    string public constant BASE_RPC_URL = "https://mainnet.base.org";

    function setUp() public {
        vm.createSelectFork(BASE_RPC_URL, 43189435);

        stableToken = new StableToken();
        shakyToken = new ShakyToken();

        collTemplate = new Collateral("Short Template", "SHORT");
        optionTemplate = new Option("Long Template", "LONG");
        factory = new Factory(address(collTemplate), address(optionTemplate));
    }

    function test_CloneGas() public {
        uint256 gasBefore = gasleft();
        address coll_ = Clones.clone(address(collTemplate));
        uint256 gasClone1 = gasBefore - gasleft();

        gasBefore = gasleft();
        address option_ = Clones.clone(address(optionTemplate));
        uint256 gasClone2 = gasBefore - gasleft();

        console.log("Clone Collateral gas:", gasClone1);
        console.log("Clone Option gas:", gasClone2);
        console.log("Total Clone gas:", gasClone1 + gasClone2);

        coll_; // silence unused
        option_;
    }
}
