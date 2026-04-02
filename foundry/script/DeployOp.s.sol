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
import { YieldVault } from "../contracts/YieldVault.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @notice Mines the address and deploys the PointsHook.sol Hook contract
contract DeployOp is Script, ScaffoldETHDeploy {
    function setUp() public { }

    function run() public ScaffoldEthDeployerRunner {
        StableToken stableToken = new StableToken();
        ShakyToken shakyToken = new ShakyToken();

        Redemption short = new Redemption(
            "Redemption", "RDM", address(stableToken), address(shakyToken), block.timestamp + 1 days, 100, false
        );

        Option long = new Option("Option", "OPT", address(short));

        // Deploy factory directly
        OptionFactory factory = new OptionFactory(address(short), address(long));

        console.log("OptionFactory deployed at:", address(factory));

        YieldVault shakyVault =
            new YieldVault(IERC20(address(shakyToken)), "Greek Shaky Vault", "gSHAKY", address(factory));
        console.log("Shaky Vault deployed at:", address(shakyVault));

        YieldVault stableVault =
            new YieldVault(IERC20(address(stableToken)), "Greek Stable Vault", "gSTABLE", address(factory));
        console.log("Stable Vault deployed at:", address(stableVault));

        // address deployer = ConstantsUnichain.CREATE2_DEPLOYER;
        // // Deploy OpHook using HookMiner to get correct address
        // uint160 flags = Hooks.BEFORE_ADD_LIQUIDITY_FLAG | Hooks.BEFORE_SWAP_FLAG | Hooks.BEFORE_DONATE_FLAG
        //     | Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG;
        // bytes memory constructorArgs = abi.encode(ConstantsUnichain.POOLMANAGER, ConstantsUnichain.PERMIT2);

        // (address hookAddress, bytes32 salt) =
        //     HookMiner.find(deployer, flags, type(OpHook).creationCode, constructorArgs);

        // console.log("Address", hookAddress);

        // OpHook opHook = new OpHook{ salt: salt }(ConstantsUnichain.POOLMANAGER, ConstantsUnichain.PERMIT2);

        // console.log("Address", hookAddress);
        // console.log("Address", address(opHook));

        // require(address(opHook) == hookAddress, " hook address mismatch");
    }
}
