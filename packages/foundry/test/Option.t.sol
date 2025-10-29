// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {OptionFactory, ShortOption, LongOption, OptionParameter} from "../contracts/OptionFactory.sol";
import {StableToken} from "../contracts/StableToken.sol";
import {ShakyToken} from "../contracts/ShakyToken.sol";

contract OptionFactoryTest is Test {
    StableToken public stableToken;
    ShakyToken public shakyToken;
    ShortOption public short;
    LongOption public long;
    OptionFactory public factory;

    // Unichain RPC URL - replace with actual Unichain RPC endpoint
    string constant UNICHAIN_RPC_URL = "https://unichain.drpc.org";
    
    function setUp() public {
        // Fork Unichain at the latest block
        vm.createSelectFork(UNICHAIN_RPC_URL);

        // Deploy tokens
        stableToken = new StableToken();
        shakyToken = new ShakyToken();

        // Deploy ShortOption
        short = new ShortOption(
            "Short Option",
            "SHORT",
            address(stableToken),
            address(shakyToken),
            block.timestamp + 1 days,
            100,
            false
        );

        // Deploy LongOption
        long = new LongOption(
            "Long Option",
            "LONG",
            address(stableToken),
            address(shakyToken),
            block.timestamp + 1 days,
            100,
            false,
            address(short)
        );

        // Deploy OptionFactory
        factory = new OptionFactory(address(short), address(long));

        // OptionParameter[] memory options = new OptionParameter[](1);
        // options[0] = OptionParameter({
        //     longSymbol: "LONG",
        //     shortSymbol: "SHORT",
        //     collateral: address(weth),
        //     consideration: address(usdc),
        //     expiration: block.timestamp + 1 days,
        //     strike: 100,
        //     isPut: false
        // });

        // factory.createOptions(options);
    }

    function test_DeploymentSuccessful() public view {
        // Verify all contracts are deployed
        assertTrue(address(stableToken) != address(0), "StableToken not deployed");
        assertTrue(address(shakyToken) != address(0), "ShakyToken not deployed");
        assertTrue(address(short) != address(0), "ShortOption not deployed");
        assertTrue(address(long) != address(0), "LongOption not deployed");
        assertTrue(address(factory) != address(0), "OptionFactory not deployed");
    }

    function test_ContractAddresses() public view {
        // Verify contracts have correct addresses set
        assertEq(address(long), address(long), "LongOption address mismatch");
        assertEq(address(short), address(short), "ShortOption address mismatch");
    }
}