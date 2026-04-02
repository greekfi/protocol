// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { Script, console } from "forge-std/Script.sol";
import { ScaffoldETHDeploy } from "./DeployHelpers.s.sol";

import { Hooks } from "@uniswap/v4-core/src/libraries/Hooks.sol";
import { HookMiner } from "@uniswap/v4-periphery/src/utils/HookMiner.sol";

import { OpHook } from "../contracts/OpHook.sol";
import { ConstantsUnichain } from "../contracts/ConstantsUnichain.sol";

import { OptionFactory, Redemption, Option } from "../contracts/OptionFactory.sol";
import { ShakyToken, StableToken } from "../contracts/ShakyToken.sol";

/// @notice Deploys the OptionFactory and OpHook
contract DeployUpgradeable is Script, ScaffoldETHDeploy {
    function setUp() public { }

    function run() public scaffoldEthDeployerRunner {
        // Deploy test tokens
        StableToken stableToken = new StableToken();
        ShakyToken shakyToken = new ShakyToken();

        // Deploy template contracts (these are used for cloning)
        Redemption redemptionTemplate = new Redemption(
            "Redemption", "RDM", address(stableToken), address(shakyToken), block.timestamp + 1 days, 100, false
        );

        Option optionTemplate = new Option("Option", "OPT", address(redemptionTemplate));

        // Deploy OptionFactory
        OptionFactory factory = new OptionFactory(address(redemptionTemplate), address(optionTemplate));

        console.log("OptionFactory deployed at:", address(factory));
        console.log("Factory owner:", factory.owner());
        console.log("Redemption template:", factory.REDEMPTION_CLONE());
        console.log("Option template:", factory.OPTION_CLONE());

        // Deploy OpHook using HookMiner to get correct address
        address deployer = ConstantsUnichain.CREATE2_DEPLOYER;
        uint160 flags = Hooks.BEFORE_ADD_LIQUIDITY_FLAG | Hooks.BEFORE_SWAP_FLAG | Hooks.BEFORE_DONATE_FLAG
            | Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG;
        bytes memory constructorArgs = abi.encode(ConstantsUnichain.POOLMANAGER, ConstantsUnichain.PERMIT2);

        (address hookAddress, bytes32 salt) =
            HookMiner.find(deployer, flags, type(OpHook).creationCode, constructorArgs);

        console.log("Calculated Hook Address:", hookAddress);

        OpHook opHook = new OpHook{ salt: salt }(ConstantsUnichain.POOLMANAGER, ConstantsUnichain.PERMIT2);

        console.log("Deployed Hook Address:", address(opHook));
        require(address(opHook) == hookAddress, "Hook address mismatch");
    }
}
