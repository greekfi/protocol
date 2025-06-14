// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./DeployHelpers.s.sol";
import "../contracts/OptionFactory.sol";

/**
 * @notice Deploy script for YourContract contract
 * @dev Inherits ScaffoldETHDeploy which:
 *      - Includes forge-std/Script.sol for deployment
 *      - Includes ScaffoldEthDeployerRunner modifier
 *      - Provides `deployer` variable
 * Example:
 * yarn deploy --file DeployYourContract.s.sol  # local anvil chain
 * yarn deploy --file DeployYourContract.s.sol --network optimism # live network (requires keystore)
 */
contract DeployYourContract is ScaffoldETHDeploy {
    /**
     * @dev Deployer setup based on `ETH_KEYSTORE_ACCOUNT` in `.env`:
     *      - "scaffold-eth-default": Uses Anvil's account #9 (0xa0Ee7A142d267C1f36714E4a8F75612F20a79720), no password prompt
     *      - "scaffold-eth-custom": requires password used while creating keystore
     *
     * Note: Must use ScaffoldEthDeployerRunner modifier to:
     *      - Setup correct `deployer` account and fund it
     *      - Export contract addresses & ABIs to `nextjs` packages
     */
    function run() external ScaffoldEthDeployerRunner {
        ShortOption short =
            new ShortOption("Short Option", "SHORT", deployer, deployer, block.timestamp + 1 days, 100, false);

        LongOption long = new LongOption(
            "Long Option", "LONG", deployer, deployer, block.timestamp + 1 days, 100, false, address(short)
        );

        OptionFactory optionFactory = new OptionFactory(address(short), address(long));

        deployments.push(Deployment("ShortOption", address(short)));
        deployments.push(Deployment("LongOption", address(long)));
        deployments.push(Deployment("OptionFactory", address(optionFactory)));
    }
}
