// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { ScaffoldETHDeploy } from "./DeployHelpers.s.sol";
import { Factory } from "../contracts/Factory.sol";
import { Receipt as Rct } from "../contracts/Receipt.sol";
import { Option } from "../contracts/Option.sol";
import { ShakyToken, StableToken } from "../contracts/mocks/ShakyToken.sol";

contract DeployYourContract is ScaffoldETHDeploy {
    function run() external broadcast {
        StableToken stableToken = new StableToken();
        ShakyToken shakyToken = new ShakyToken();
        stableToken;
        shakyToken;

        Rct receiptTpl = new Rct("Rct", "RCT");
        Option optionTpl = new Option("Option", "OPT");

        new Factory(address(receiptTpl), address(optionTpl));
    }
}
