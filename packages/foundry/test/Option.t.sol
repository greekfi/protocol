// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test, console} from "forge-std/Test.sol";
import {OptionFactory, ShortOption, LongOption, OptionParameter} from "../contracts/OptionFactory.sol";
import {StableToken} from "../contracts/StableToken.sol";
import {ShakyToken} from "../contracts/ShakyToken.sol";
import {IPermit2} from "../contracts/interfaces/IPermit2.sol";

contract OptionTest is Test {
    StableToken public stableToken;
    ShakyToken public shakyToken;
    ShortOption public short;
    LongOption public long;
    OptionFactory public factory;

    IPermit2 permit2 = IPermit2(PERMIT2);

    // Unichain RPC URL - replace with actual Unichain RPC endpoint
    string constant UNICHAIN_RPC_URL = "https://unichain.drpc.org";
    address constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;

    uint160 constant MAX160 = type(uint160).max;
    uint48 constant MAX48 = type(uint48).max;
    uint256 constant MAX256 = type(uint256).max;
    
    function setUp() public {
        // Fork Unichain at the latest block
        vm.createSelectFork(UNICHAIN_RPC_URL);

        // Deploy tokens
        stableToken = new StableToken();
        shakyToken = new ShakyToken();

        // Mint tokens to test address
        stableToken.mint(address(this), 1_000_000 * 10**18);
        shakyToken.mint(address(this), 1_000_000 * 10**18);

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


        OptionParameter[] memory options = new OptionParameter[](1);
        options[0] = OptionParameter({
            longSymbol: "LONG",
            shortSymbol: "SHORT",
            collateral: address(shakyToken),
            consideration: address(stableToken),
            expiration: block.timestamp + 1 days,
            strike: 1e18,
            isPut: false
        });

        factory.createOptions(options);
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

    function test_Mint() public {
        // Placeholder for exercise test logic
        address[] memory options = factory.getCreatedOptions();
        LongOption longOption = LongOption(options[0]);
        shakyToken.approve(longOption.shortOption(), type(uint256).max);
        longOption.mint(1);

        // console.log("Exercise test executed");

    }


    function test_Exercise1() public {
        // Placeholder for exercise test logic
        address[] memory options = factory.getCreatedOptions();
        LongOption longOption = LongOption(options[0]);
        // shakyToken.approve(longOption.shortOption(), 1000 * 10**18);
        shakyToken.approve(PERMIT2, MAX256);
        permit2.approve(address(shakyToken), longOption.shortOption(), MAX160, MAX48);
        longOption.mint(1);

        // console.log("Exercise test executed");

    }

    function test_Transfer() public {
        // Placeholder for transfer test logic
        address[] memory options = factory.getCreatedOptions();
        LongOption longOption = LongOption(options[0]);
        shakyToken.approve(longOption.shortOption(), type(uint256).max);
        // longOption.mint(1);

        longOption.transfer(address(0x123), 1);

        // console.log("Transfer test executed");
    }


    function test_Transfer1() public {
        // Placeholder for transfer test logic
        address[] memory options = factory.getCreatedOptions();
        LongOption longOption = LongOption(options[0]);
        // shakyToken.approve(longOption.shortOption(), type(uint256).max);
        // longOption.mint(1);
        shakyToken.approve(PERMIT2, MAX256);
        permit2.approve(address(shakyToken), longOption.shortOption(), MAX160, MAX48);


        longOption.transfer(address(0x123), 1);

        console.log("Transfer test executed", shakyToken.balanceOf(address(this)) );
        console.log("Transfer test executed", longOption.shortOption_().balanceOf(address(this)) );
    }



    function test_TransferFrom1() public {
        // Placeholder for transfer test logic
        address[] memory options = factory.getCreatedOptions();
        LongOption longOption = LongOption(options[0]);
        // shakyToken.approve(longOption.shortOption(), type(uint256).max);
        // longOption.mint(1);
        shakyToken.approve(PERMIT2, MAX256);
        permit2.approve(address(shakyToken), longOption.shortOption(), MAX160, MAX48);


        longOption.transfer(address(0x123), 1);

        vm.prank(address(0x123));
        longOption.approve(address(this), 1);
        longOption.transferFrom(address(0x123), address(this), 1);

        console.log("Transfer test executed", shakyToken.balanceOf(address(this)) );
        console.log("Transfer test executed", longOption.shortOption_().balanceOf(address(this)) );
    }


    function test_TransferTransfer() public {
        // Placeholder for transfer test logic
        address[] memory options = factory.getCreatedOptions();
        LongOption longOption = LongOption(options[0]);
        // shakyToken.approve(longOption.shortOption(), type(uint256).max);
        // longOption.mint(1);
        shakyToken.approve(PERMIT2, MAX256);
        permit2.approve(address(shakyToken), longOption.shortOption(), MAX160, MAX48);


        longOption.transfer(address(0x123), 1);

        vm.prank(address(0x123));
        longOption.transfer( address(this), 1);

        console.log("Transfer test executed", shakyToken.balanceOf(address(this)) );
        console.log("Transfer test executed", longOption.shortOption_().balanceOf(address(this)) );
    }

    function test_Exercise() public {
        // Placeholder for transfer test logic
        address[] memory options = factory.getCreatedOptions();
        LongOption longOption = LongOption(options[0]);
        // shakyToken.approve(longOption.shortOption(), type(uint256).max);
        shakyToken.approve(PERMIT2, MAX256);
        permit2.approve(address(shakyToken), longOption.shortOption(), MAX160, MAX48);
        stableToken.approve(PERMIT2, MAX256);
        permit2.approve(address(stableToken), longOption.shortOption(), MAX160, MAX48);
        longOption.mint(1);
        longOption.exercise(1);

        // vm.prank(address(0x123));
        // longOption.transfer( address(this), 1);

        console.log("Transfer test executed", shakyToken.balanceOf(address(this)) );
        console.log("Transfer test executed", longOption.shortOption_().balanceOf(address(this)) );
    }
}