// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { Script, console } from "forge-std/Script.sol";
import { ScaffoldETHDeploy } from "./DeployHelpers.s.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import { Hooks } from "@uniswap/v4-core/src/libraries/Hooks.sol";
import { HookMiner } from "@uniswap/v4-periphery/src/utils/HookMiner.sol";

import { OpHook } from "../contracts/OpHook.sol";
import { ConstantsUnichain } from "../contracts/ConstantsUnichain.sol";

import { OptionFactory, Redemption, Option } from "../contracts/OptionFactory.sol";
import { ShakyToken, StableToken } from "../contracts/ShakyToken.sol";

/// @notice Deploys the upgradeable OptionFactory using UUPS proxy pattern
contract DeployUpgradeable is Script, ScaffoldETHDeploy {
    function setUp() public { }

    function run() public ScaffoldEthDeployerRunner {
        // Deploy test tokens
        StableToken stableToken = new StableToken();
        ShakyToken shakyToken = new ShakyToken();

        // Deploy template contracts (these are used for cloning, not upgraded)
        Redemption redemptionTemplate = new Redemption(
            "Redemption", "RDM", address(stableToken), address(shakyToken), block.timestamp + 1 days, 100, false
        );

        Option optionTemplate = new Option("Option", "OPT", address(redemptionTemplate));

        // Deploy OptionFactory implementation (logic contract)
        OptionFactory implementation = new OptionFactory();

        console.log("OptionFactory Implementation deployed at:", address(implementation));

        // Encode the initialize function call
        bytes memory initData = abi.encodeCall(
            OptionFactory.initialize, (address(redemptionTemplate), address(optionTemplate), 0.0001e18)
        );

        // Deploy ERC1967Proxy with implementation and initialization data
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);

        console.log("ERC1967Proxy deployed at:", address(proxy));

        // The factory is now accessible through the proxy address
        OptionFactory factory = OptionFactory(address(proxy));

        console.log("OptionFactory (via proxy) at:", address(factory));
        console.log("Factory owner:", factory.owner());
        console.log("Factory fee:", factory.fee());
        console.log("Redemption template:", factory.redemptionClone());
        console.log("Option template:", factory.optionClone());

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
