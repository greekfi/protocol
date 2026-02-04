// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { Script, console } from "forge-std/Script.sol";
import { IERC20 } from "forge-std/interfaces/IERC20.sol";

/// @notice Gas-efficient batch approval script
/// @dev Sends all approvals in a single transaction from the caller's address
contract BatchApproveScript is Script {
    function run() external {
        // Read configuration from environment
        address spender = vm.envAddress("APPROVER");
        string memory filename = vm.envOr("FILE", string("options.txt"));

        // Parse addresses from file
        address[] memory tokens = parseAddressFile(filename);

        console.log("========================================");
        console.log("     Batch Approval Configuration      ");
        console.log("========================================");
        console.log("File:            ", filename);
        console.log("Tokens:          ", tokens.length);
        console.log("Spender:         ", spender);
        console.log("");

        vm.startBroadcast();

        uint256 successCount = 0;

        console.log("Approving tokens...");
        console.log("");

        // Approve all tokens in a single transaction
        for (uint256 i = 0; i < tokens.length; i++) {
            address token = tokens[i];

            try IERC20(token).approve(spender, type(uint256).max) returns (bool success) {
                if (success) {
                    console.log("[%d/%d] OK  ", i + 1, tokens.length, token);
                    successCount++;
                } else {
                    console.log("[%d/%d] FAIL (returned false)", i + 1, tokens.length, token);
                }
            } catch Error(string memory reason) {
                console.log("[%d/%d] FAIL:", i + 1, tokens.length, token);
                console.log("         Reason:", reason);
            } catch {
                console.log("[%d/%d] FAIL (unknown error)", i + 1, tokens.length, token);
            }
        }

        vm.stopBroadcast();

        console.log("");
        console.log("========================================");
        console.log("          Approval Summary              ");
        console.log("========================================");
        console.log("Successful:      ", successCount, "/", tokens.length);
        console.log("");
        console.log("Done!");
    }

    /// @notice Parse addresses from text file
    function parseAddressFile(string memory filename) internal view returns (address[] memory) {
        string memory file = vm.readFile(filename);
        string[] memory lines = vm.split(file, "\n");

        // Parse addresses in a single pass
        address[] memory tempTokens = new address[](lines.length);
        uint256 count = 0;

        for (uint256 i = 0; i < lines.length; i++) {
            string memory trimmed = vm.trim(lines[i]);
            bytes memory trimmedBytes = bytes(trimmed);

            // Only parse lines that look like addresses (start with "0x", at least 42 chars)
            if (trimmedBytes.length >= 42 && trimmedBytes[0] == "0" && trimmedBytes[1] == "x") {
                tempTokens[count] = vm.parseAddress(trimmed);
                count++;
            }
        }

        // Create right-sized array
        address[] memory tokens = new address[](count);
        for (uint256 i = 0; i < count; i++) {
            tokens[i] = tempTokens[i];
        }

        return tokens;
    }
}
