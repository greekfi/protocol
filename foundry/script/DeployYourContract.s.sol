// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { ScaffoldETHDeploy } from "./DeployHelpers.s.sol";
import { Factory } from "../contracts/Factory.sol";
import { Collateral } from "../contracts/Collateral.sol";
import { Option } from "../contracts/Option.sol";
import { ShakyToken, StableToken } from "../contracts/ShakyToken.sol";

contract DeployYourContract is ScaffoldETHDeploy {
    function run() external broadcast {
        StableToken stableToken = new StableToken();
        ShakyToken shakyToken = new ShakyToken();
        stableToken;
        shakyToken;

        Collateral short = new Collateral("Collateral", "COLL");
        Option long = new Option("Option", "OPT");

        new Factory(address(short), address(long));
    }
}
