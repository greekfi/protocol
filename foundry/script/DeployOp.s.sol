// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { Script, console } from "forge-std/Script.sol";
import { ScaffoldETHDeploy } from "./DeployHelpers.s.sol";

import { Factory } from "../contracts/Factory.sol";
import { Receipt as Rct } from "../contracts/Receipt.sol";
import { Option } from "../contracts/Option.sol";
import { ShakyToken, StableToken } from "../contracts/mocks/ShakyToken.sol";
import { YieldVault } from "../contracts/YieldVault.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract DeployOp is Script, ScaffoldETHDeploy {
    function setUp() public { }

    function run() public broadcast {
        StableToken stableToken = new StableToken();
        ShakyToken shakyToken = new ShakyToken();

        Rct receiptTpl = new Rct("Rct", "RCT");
        Option optionTpl = new Option("Option", "OPT");

        Factory factory = new Factory();
        console.log("Factory deployed at:", address(factory));

        YieldVault shakyVault =
            new YieldVault(IERC20(address(shakyToken)), "Greek Shaky Vault", "gSHAKY", address(factory));
        console.log("Shaky Vault deployed at:", address(shakyVault));

        YieldVault stableVault =
            new YieldVault(IERC20(address(stableToken)), "Greek Stable Vault", "gSTABLE", address(factory));
        console.log("Stable Vault deployed at:", address(stableVault));
    }
}
