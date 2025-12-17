// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { Test, console } from "forge-std/Test.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { OptionFactory, Redemption, Option, OptionParameter } from "../contracts/OptionFactory.sol";
import { Balances } from "../contracts/Option.sol";
import { StableToken } from "../contracts/StableToken.sol";
import { ShakyToken } from "../contracts/ShakyToken.sol";
import { IPermit2 } from "../contracts/interfaces/IPermit2.sol";

/**
 * @title GasAnalysis
 * @notice Comprehensive gas analysis for Factory, Option, and Redemption contracts
 * @dev Each test measures gas for a specific function. Run with --gas-report flag.
 */
contract GasAnalysis is Test {
    using SafeERC20 for IERC20;

    // Contracts
    StableToken public stableToken;
    ShakyToken public shakyToken;
    Redemption public redemptionTemplate;
    Option public optionTemplate;
    OptionFactory public factory;

    // Deployed via factory
    Option public option;
    Redemption public redemption;

    // Permit2
    IPermit2 public permit2 = IPermit2(PERMIT2);

    // Constants
    string public constant UNICHAIN_RPC_URL = "https://unichain.drpc.org";
    address public constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;
    uint160 public constant MAX160 = type(uint160).max;
    uint48 public constant MAX48 = type(uint48).max;
    uint256 public constant MAX256 = type(uint256).max;

    function setUp() public {
        // Fork Unichain
        vm.createSelectFork(UNICHAIN_RPC_URL);

        // Deploy test tokens
        stableToken = new StableToken();
        shakyToken = new ShakyToken();

        // Mint tokens to test contract
        stableToken.mint(address(this), 1_000_000 * 10 ** 18);
        shakyToken.mint(address(this), 1_000_000 * 10 ** 18);

        // Deploy template contracts (these will be cloned by factory)
        redemptionTemplate = new Redemption(
            "Short Template", "SHORT", address(stableToken), address(shakyToken), block.timestamp + 1 days, 1e18, false
        );

        optionTemplate = new Option("Long Template", "LONG", address(redemptionTemplate));

        // Deploy factory
        factory = new OptionFactory(
            address(redemptionTemplate),
            address(optionTemplate),
            0.0001e18 // 0.01% fee
        );

        // Create an option pair via factory (required for testing Option/Redemption)
        OptionParameter[] memory params = new OptionParameter[](1);
        params[0] = OptionParameter({
            collateral_: address(shakyToken),
            consideration_: address(stableToken),
            expiration: uint40(block.timestamp + 30 days),
            strike: uint96(1e18),
            isPut: false
        });

        address optionAddress = factory.createOption(
            params[0].collateral_, params[0].consideration_, params[0].expiration, params[0].strike, params[0].isPut
        );

        // Get the deployed option and redemption
        option = Option(optionAddress);
        redemption = option.redemption();

        // Setup approvals for testing
        _setupApprovals();
    }

    function _setupApprovals() internal {
        // Approve Permit2
        IERC20(address(stableToken)).approve(address(factory), MAX256);
        IERC20(address(shakyToken)).approve(address(factory), MAX256);

        // Approve factory via Permit2
        // permit2.approve(address(stableToken), address(factory), MAX160, MAX48);
        // permit2.approve(address(shakyToken), address(factory), MAX160, MAX48);
    }

    // ============================================
    // FACTORY GAS TESTS
    // ============================================

    function test_Gas_Factory_CreateOption() public {
        OptionParameter[] memory params = new OptionParameter[](1);
        params[0] = OptionParameter({
            collateral_: address(shakyToken),
            consideration_: address(stableToken),
            expiration: uint40(block.timestamp + 60 days),
            strike: uint96(2e18),
            isPut: false
        });

        factory.createOptions(params);
    }

    function test_Gas_Factory_CreateOption_DirectCall() public {
        factory.createOption(address(shakyToken), address(stableToken), uint40(block.timestamp + 60 days), 2e18, false);
    }

    function test_Gas_Factory_CreateMultipleOptions_3() public {
        OptionParameter[] memory params = new OptionParameter[](3);

        for (uint256 i = 0; i < 3; i++) {
            params[i] = OptionParameter({
                collateral_: address(shakyToken),
                consideration_: address(stableToken),
                expiration: uint40(block.timestamp + 30 days + (i * 1 days)),
                strike: uint96(1e18 + (i * 0.1e18)),
                isPut: false
            });
        }

        factory.createOptions(params);
    }

    function test_Gas_Factory_CreateMultipleOptions_16() public {
        OptionParameter[] memory params = new OptionParameter[](16);

        for (uint256 i = 0; i < 16; i++) {
            params[i] = OptionParameter({
                collateral_: address(shakyToken),
                consideration_: address(stableToken),
                expiration: uint40(block.timestamp + 30 days + (i * 1 days)),
                strike: uint96(1e18 + (i * 0.1e18)),
                isPut: false
            });
        }

        factory.createOptions(params);
    }

    // Helper function to convert uint to string
    function _toString(uint256 value) internal pure returns (string memory) {
        if (value == 0) {
            return "0";
        }
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }

    // ============================================
    // OPTION GAS TESTS - CORE FUNCTIONS
    // ============================================

    function test_Gas_Option_Mint_1Token() public {
        option.mint(1);
    }

    function test_Gas_Option_Mint_10Tokens() public {
        option.mint(10);
    }

    function test_Gas_Option_Mint_100Tokens() public {
        option.mint(100);
    }

    function test_Gas_Option_Mint_1000Tokens() public {
        option.mint(1000);
    }

    function test_Gas_Option_MintToAddress() public {
        // Need to fund the address first with collateral
        shakyToken.mint(address(0x123), 1000e18);

        vm.startPrank(address(0x123));
        IERC20(address(shakyToken)).approve(address(factory), MAX256);
        // permit2.approve(address(shakyToken), address(factory), MAX160, MAX48);
        option.mint(address(0x123), 10);
        vm.stopPrank();
    }

    function test_Gas_Option_Exercise_1Token() public {
        option.mint(1);
        option.exercise(1);
    }

    function test_Gas_Option_Exercise_10Tokens() public {
        option.mint(10);
        option.exercise(10);
    }

    function test_Gas_Option_Exercise_Partial() public {
        option.mint(100);
        option.exercise(50);
    }

    function test_Gas_Option_Redeem_1Token() public {
        option.mint(1);
        option.redeem(1);
    }

    function test_Gas_Option_Redeem_10Tokens() public {
        option.mint(10);
        option.redeem(10);
    }

    function test_Gas_Option_Redeem_Partial() public {
        option.mint(100);
        option.redeem(50);
    }

    function test_Gas_Option_RedeemWithAddress() public {
        option.mint(10);
        option.redeem(address(this), 5);
    }

    // ============================================
    // OPTION GAS TESTS - TRANSFERS
    // ============================================

    function test_Gas_Option_Transfer() public {
        option.mint(10);
        IERC20(address(option)).transfer(address(0x123), 5);
    }

    function test_Gas_Option_Transfer_AutoMint() public {
        // Transfer more than balance triggers auto-mint
        IERC20(address(option)).transfer(address(0x123), 5);
    }

    function test_Gas_Option_TransferFrom() public {
        option.mint(10);
        option.approve(address(this), 10);
        option.transferFrom(address(this), address(0x123), 5);
    }

    function test_Gas_Option_TransferFrom_AutoRedeem() public {
        option.mint(10);
        IERC20(address(option)).transfer(address(0x123), 5);

        vm.prank(address(0x123));
        option.approve(address(this), 10);

        // TransferFrom back triggers auto-redeem
        option.transferFrom(address(0x123), address(this), 3);
    }

    function test_Gas_Option_Approve() public {
        option.approve(address(0x123), 100);
    }

    // ============================================
    // OPTION GAS TESTS - VIEW FUNCTIONS
    // ============================================

    function test_Gas_Option_BalanceOf() public view {
        option.balanceOf(address(this));
    }

    function test_Gas_Option_BalancesOf() public {
        option.mint(10);
        option.balancesOf(address(this));
    }

    function test_Gas_Option_Details() public view {
        option.details();
    }

    function test_Gas_Option_CollateralData() public view {
        redemption.collateralData();
    }

    function test_Gas_Option_ConsiderationData() public view {
        redemption.considerationData();
    }

    function test_Gas_Option_ToConsideration() public view {
        redemption.toConsideration(1e18);
    }

    function test_Gas_Option_ToCollateral() public view {
        redemption.toCollateral(1e18);
    }

    // ============================================
    // OPTION GAS TESTS - ADMIN FUNCTIONS
    // ============================================

    function test_Gas_Option_Lock() public {
        option.lock();
    }

    function test_Gas_Option_Unlock() public {
        option.lock();
        option.unlock();
    }

    // ============================================
    // REDEMPTION GAS TESTS - CORE FUNCTIONS
    // ============================================

    function test_Gas_Redemption_Mint() public {
        // Only callable by option contract
        vm.prank(address(option));
        redemption.mint(address(this), 10);
    }

    function test_Gas_Redemption_Exercise() public {
        option.mint(10);

        // Only callable by option contract
        vm.prank(address(option));
        redemption.exercise(address(this), 5, address(this));
    }

    function test_Gas_Redemption_Redeem_PreExpiration() public {
        option.mint(10);

        // Redeem via option contract's internal function before expiration
        vm.prank(address(option));
        redemption._redeemPair(address(this), 5);
    }

    function test_Gas_Redemption_Redeem_PostExpiration() public {
        option.mint(10);

        // Warp past expiration
        vm.warp(block.timestamp + 31 days);

        // Redeem directly after expiration
        redemption.redeem(5);
    }

    function test_Gas_Redemption_RedeemConsideration() public {
        option.mint(10);
        option.exercise(5);

        // Redeem using consideration tokens
        redemption.redeemConsideration(5);
    }

    function test_Gas_Redemption_Sweep_SingleUser() public {
        option.mint(10);

        // Warp past expiration
        vm.warp(block.timestamp + 31 days);

        // Sweep for single user
        redemption.sweep(address(this));
    }

    function test_Gas_Redemption_Sweep_MultipleUsers() public {
        option.mint(10);

        // Distribute to multiple users
        IERC20(address(redemption)).transfer(address(0x123), 3);
        IERC20(address(redemption)).transfer(address(0x456), 3);

        // Warp past expiration
        vm.warp(block.timestamp + 31 days);

        // Sweep for multiple users
        address[] memory users = new address[](3);
        users[0] = address(this);
        users[1] = address(0x123);
        users[2] = address(0x456);

        for (uint256 i = 0; i < users.length; i++) {
            if (redemption.balanceOf(users[i]) > 0) {
                redemption.sweep(users[i]);
            }
        }
    }

    // ============================================
    // REDEMPTION GAS TESTS - TRANSFERS
    // ============================================

    function test_Gas_Redemption_Transfer() public {
        option.mint(10);
        IERC20(address(redemption)).transfer(address(0x123), 5);
    }

    function test_Gas_Redemption_TransferFrom() public {
        option.mint(10);
        redemption.approve(address(this), 10);
        redemption.transferFrom(address(this), address(0x123), 5);
    }

    function test_Gas_Redemption_Approve() public {
        redemption.approve(address(0x123), 100);
    }

    // ============================================
    // REDEMPTION GAS TESTS - VIEW FUNCTIONS
    // ============================================

    function test_Gas_Redemption_BalanceOf() public view {
        redemption.balanceOf(address(this));
    }

    function test_Gas_Redemption_BalancesOf() public {
        option.mint(10);
        option.balancesOf(address(this));
    }

    function test_Gas_Redemption_CollateralData() public view {
        redemption.collateralData();
    }

    function test_Gas_Redemption_ConsiderationData() public view {
        redemption.considerationData();
    }

    // ============================================
    // REDEMPTION GAS TESTS - ADMIN FUNCTIONS
    // ============================================

    function test_Gas_Redemption_Lock() public {
        // Only owner (Option contract) can lock
        vm.prank(address(option));
        redemption.lock();
    }

    function test_Gas_Redemption_Unlock() public {
        // Only owner (Option contract) can lock/unlock
        vm.prank(address(option));
        redemption.lock();

        vm.prank(address(option));
        redemption.unlock();
    }

    // ============================================
    // COMPLEX WORKFLOW GAS TESTS
    // ============================================

    function test_Gas_Workflow_FullLifecycle() public {
        // Mint
        option.mint(100);

        // Transfer some options
        IERC20(address(option)).transfer(address(0x123), 30);

        // Exercise some
        option.exercise(20);

        // Redeem some
        option.redeem(30);

        // Check balances
        option.balancesOf(address(this));
    }

    function test_Gas_Workflow_MultipleUsers() public {
        // User 1 mints
        option.mint(100);

        // Transfer to user 2
        IERC20(address(option)).transfer(address(0x123), 50);

        // User 2 exercises
        stableToken.mint(address(0x123), 1000e18);
        vm.startPrank(address(0x123));
        IERC20(address(stableToken)).approve(address(factory), MAX256);
        // permit2.approve(address(stableToken), address(factory), MAX160, MAX48);
        option.exercise(25);
        vm.stopPrank();

        // User 1 redeems
        option.redeem(40);
    }

    function test_Gas_Workflow_PostExpiration() public {
        // Mint options
        option.mint(100);

        // Exercise some
        option.exercise(30);

        // Warp past expiration
        vm.warp(block.timestamp + 31 days);

        // Redeem redemption tokens
        redemption.redeem(70);
    }

    // ============================================
    // DEPLOYMENT GAS TESTS
    // ============================================

    function test_Gas_Deploy_StableToken() public {
        new StableToken();
    }

    function test_Gas_Deploy_ShakyToken() public {
        new ShakyToken();
    }

    function test_Gas_Deploy_RedemptionTemplate() public {
        new Redemption(
            "Short Template", "SHORT", address(stableToken), address(shakyToken), block.timestamp + 1 days, 1e18, false
        );
    }

    function test_Gas_Deploy_OptionTemplate() public {
        new Option("Long Template", "LONG", address(redemptionTemplate));
    }

    function test_Gas_Deploy_Factory() public {
        new OptionFactory(address(redemptionTemplate), address(optionTemplate),  0.0001e18);
    }
}
