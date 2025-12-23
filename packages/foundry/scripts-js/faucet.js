#!/usr/bin/env node
import { execSync } from "child_process";

/**
 * Faucet script for local Anvil development
 * Sends ETH to a specified address on localhost:8545
 *
 * Usage:
 *   yarn faucet <address> [amount]
 *   yarn faucet 0x1234... 100
 *
 * Defaults to 10000 ETH if amount not specified
 */

const DEFAULT_AMOUNT = "10000";
const RPC_URL = "http://localhost:8545";

// Parse command line arguments
const args = process.argv.slice(2);

if (args.length === 0) {
  console.error("\n❌ Error: Address required");
  console.log("\nUsage:");
  console.log("  yarn faucet <address> [amount]");
  console.log("\nExample:");
  console.log("  yarn faucet 0x742d35Cc6634C0532925a3b844Bc454e4438f44e 100");
  console.log("\nDefaults to 10000 ETH if amount not specified");
  process.exit(1);
}

const address = args[0];
const amountEth = args[1] || DEFAULT_AMOUNT;

// Validate address format
if (!address.match(/^0x[a-fA-F0-9]{40}$/)) {
  console.error(`\n❌ Error: Invalid Ethereum address: ${address}`);
  console.log("Address must be 40 hex characters prefixed with 0x");
  process.exit(1);
}

// Convert ETH to wei (hex string)
const amountWei = BigInt(amountEth) * BigInt(10 ** 18);
const amountHex = "0x" + amountWei.toString(16);

// Construct JSON-RPC payload
const payload = {
  method: "anvil_setBalance",
  params: [address, amountHex],
  id: 1,
  jsonrpc: "2.0",
};

console.log(`\n💰 Sending ${amountEth} ETH to ${address}...`);

try {
  // Execute curl command
  const command = [
    "curl",
    "-s",
    "-X POST",
    RPC_URL,
    "-H 'Content-Type: application/json'",
    `--data '${JSON.stringify(payload)}'`,
  ].join(" ");

  const result = execSync(command, { encoding: "utf-8" });
  const response = JSON.parse(result);

  if (response.error) {
    console.error(`\n❌ RPC Error: ${response.error.message}`);
    console.log("\nMake sure Anvil is running on localhost:8545");
    console.log("Start it with: yarn chain");
    process.exit(1);
  }

  console.log(`✅ Success! Balance set to ${amountEth} ETH`);
  console.log(`\nVerify with: cast balance ${address} --rpc-url ${RPC_URL}\n`);
} catch (error) {
  console.error("\n❌ Failed to connect to Anvil");
  console.log("\nMake sure Anvil is running on localhost:8545");
  console.log("Start it with: yarn chain");
  console.log(`\nError: ${error.message}\n`);
  process.exit(1);
}
