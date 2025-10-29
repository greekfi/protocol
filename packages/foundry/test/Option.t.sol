// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test, console} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
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
    LongOption longOption;
    address shortOption;
    address shakyToken_;
    address stableToken_;

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
        shakyToken_ = address(shakyToken);
        stableToken_ = address(stableToken);

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


        address[] memory options1 = factory.getCreatedOptions();
        longOption = LongOption(options1[0]);
        shortOption = longOption.shortOption();
    }

    function approve1(address token, address spender) public {
        IERC20(token).approve(PERMIT2, MAX256);
        permit2.approve(token, spender, MAX160, MAX48);
    }

    function approve2(address token, address spender) public {
        IERC20(token).approve(spender, MAX256);
    }

    function consoleBalances() public view {
        console.log("ShakyToken balance:", shakyToken.balanceOf(address(this)));
        console.log("StableToken balance:", stableToken.balanceOf(address(this)));
        console.log("LongOption balance:", longOption.balanceOf(address(this)));
        console.log("ShortOption balance:", longOption.shortOption_().balanceOf(address(this)));
    }

    modifier t1 {
        approve1(shakyToken_, shortOption);
        approve1(stableToken_, shortOption);
        _;
        consoleBalances();
    }

    modifier t2 {
        approve2(shakyToken_, shortOption);
        approve2(stableToken_, shortOption);
        _;
        consoleBalances();
    }

    function test_Mint() public t1 {
        longOption.mint(1);
    }

    function test_Transfer1() public t1 {
        longOption.transfer(address(0x123), 1);
    }

    function test_Transfer2() public t2 {
        longOption.transfer(address(0x123), 1);
    }

    function test_TransferFrom1() public t1 {
        longOption.transfer(address(0x123), 1);
        vm.prank(address(0x123));
        approve2(address(longOption), address(this));
        longOption.transferFrom(address(0x123), address(this), 1);
    }

    function test_TransferTransfer() public t1 {
        longOption.transfer(address(0x123), 1);
        vm.prank(address(0x123));
        longOption.transfer( address(this), 1);
        }

    function test_Exercise1() public t1 {
        longOption.mint(1);
        longOption.exercise(1);
    }

    function test_Exercise2() public t2 {
        longOption.mint(1);
        longOption.exercise(1);
    }

    function test_Redeem1() public t1 {
        longOption.mint(1);
        longOption.redeem(1);
    }

    function test_Redeem2() public t2 {
        longOption.mint(1);
        longOption.redeem(1);
    }

    function test_RedeemConsideration1() public t1 {
        longOption.mint(1);
        longOption.exercise(1);
        longOption.shortOption_().redeemConsideration(1);
    }

    function test_RedeemConsideration2() public t2 {
        longOption.mint(1);
        longOption.exercise(1);
        longOption.shortOption_().redeemConsideration(1);
    }

}