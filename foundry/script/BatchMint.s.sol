// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { Script, console } from "forge-std/Script.sol";
import { IOption } from "../contracts/interfaces/IOption.sol";
import { IFactory } from "../contracts/interfaces/IFactory.sol";
import { IERC20 } from "forge-std/interfaces/IERC20.sol";
import { BatchMinter } from "../contracts/BatchMinter.sol";

contract BatchMintScript is Script {
    function run() external {
        uint256 amountPerOption = vm.envUint("AMOUNT_PER_OPTION");
        address batchMinterAddr = vm.envOr("BATCH_MINTER", address(0));

        // Read pre-filtered addresses
        string memory filename = vm.envOr("FILE", string("valid.txt"));
        string memory file = vm.readFile(filename);
        string[] memory lines = vm.split(file, "\n");

        // Count non-empty lines
        uint256 count = 0;
        for (uint256 i = 0; i < lines.length; i++) {
            if (bytes(lines[i]).length > 0) count++;
        }

        address[] memory options = new address[](count);
        uint256[] memory amounts = new uint256[](count);

        uint256 idx = 0;
        for (uint256 i = 0; i < lines.length; i++) {
            if (bytes(lines[i]).length == 0) continue;
            options[idx] = vm.parseAddress(lines[i]);
            amounts[idx] = amountPerOption;
            idx++;
        }

        uint256 totalAmount = amountPerOption * count;
        address factory = IOption(options[0]).factory();
        address collateral = IOption(options[0]).collateral();
        string memory symbol = IERC20(collateral).symbol();
        uint8 decimals = IERC20(collateral).decimals();

        console.log("File:", filename);
        console.log("Options:", count);
        console.log("Collateral:", symbol, collateral);
        console.log("Decimals:", decimals);
        console.log("Amount per option:", amountPerOption);
        console.log("Total collateral:", totalAmount);
        console.log("Factory:", factory);

        vm.startBroadcast();

        BatchMinter batchMinter;
        if (batchMinterAddr == address(0)) {
            batchMinter = new BatchMinter();
            console.log("Deployed BatchMinter:", address(batchMinter));
        } else {
            batchMinter = BatchMinter(batchMinterAddr);
        }

        IERC20(collateral).approve(factory, totalAmount);
        IFactory(factory).approve(collateral, totalAmount);
        batchMinter.batchMint(options, amounts);

        vm.stopBroadcast();
        console.log("Done!");
    }
}
