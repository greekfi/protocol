// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { Script, console } from "forge-std/Script.sol";
import { ScaffoldETHDeploy } from "./DeployHelpers.s.sol";

import { RFQ } from "../contracts/RFQ.sol";

contract DeployRFQ is Script, ScaffoldETHDeploy {
    function setUp() public { }

    function run() public ScaffoldEthDeployerRunner {
        RFQ rfq = new RFQ();

        console.log("Address", address(rfq));
    }
}
