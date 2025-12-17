// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { Script, console } from "forge-std/Script.sol";
import { ScaffoldETHDeploy } from "./DeployHelpers.s.sol";

import { Hooks } from "@uniswap/v4-core/src/libraries/Hooks.sol";
import { HookMiner } from "@uniswap/v4-periphery/src/utils/HookMiner.sol";

import { OpHook } from "../contracts/OpHook.sol";
import { ConstantsUnichain } from "../contracts/ConstantsUnichain.sol";

import { OptionFactory, Redemption, Option } from "../contracts/OptionFactory.sol";
import { StableToken } from "../contracts/StableToken.sol";
import { ShakyToken } from "../contracts/ShakyToken.sol";

/// @notice Mines the address and deploys the PointsHook.sol Hook contract
contract DeployOp is Script, ScaffoldETHDeploy {
    function setUp() public { }

    function run() public ScaffoldEthDeployerRunner {
        StableToken stableToken = new StableToken();
        ShakyToken shakyToken = new ShakyToken();

        Redemption short = new Redemption(
            "Redemption", "RDM", address(stableToken), address(shakyToken), block.timestamp + 1 days, 100, false
        );

        Option long = new Option(
            "Option",
            "OPT",
            address(short)
        );

        new OptionFactory(address(short), address(long), address(ConstantsUnichain.PERMIT2), 0.0001e18);

        address deployer = ConstantsUnichain.CREATE2_DEPLOYER;
        // Deploy OpHook using HookMiner to get correct address
        uint160 flags = Hooks.BEFORE_ADD_LIQUIDITY_FLAG | Hooks.BEFORE_SWAP_FLAG | Hooks.BEFORE_DONATE_FLAG
            | Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG;
        bytes memory constructorArgs = abi.encode(ConstantsUnichain.POOLMANAGER, ConstantsUnichain.PERMIT2);

        (address hookAddress, bytes32 salt) =
            HookMiner.find(deployer, flags, type(OpHook).creationCode, constructorArgs);

        console.log("Address", hookAddress);

        OpHook opHook = new OpHook{ salt: salt }(ConstantsUnichain.POOLMANAGER, ConstantsUnichain.PERMIT2);

        console.log("Address", hookAddress);
        console.log("Address", address(opHook));

        require(address(opHook) == hookAddress, " hook address mismatch");
    }
}
