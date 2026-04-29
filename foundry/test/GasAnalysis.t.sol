// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { Test } from "forge-std/Test.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Factory } from "../contracts/Factory.sol";
import { Receipt as Rct } from "../contracts/Receipt.sol";
import { Option } from "../contracts/Option.sol";
import { CreateParams } from "../contracts/interfaces/IFactory.sol";
import { ShakyToken, StableToken } from "../contracts/mocks/ShakyToken.sol";
import { IPermit2 } from "../contracts/interfaces/IPermit2.sol";

/**
 * @title GasAnalysis
 * @notice Comprehensive gas analysis for Factory, Option, and Collateral contracts
 * @dev Each test measures gas for a specific function. Run with --gas-report flag.
 */
contract GasAnalysis is Test {
    using SafeERC20 for IERC20;

    // Contracts
    StableToken public stableToken;
    ShakyToken public shakyToken;
    Rct public redemptionTemplate;
    Option public optionTemplate;
    Factory public factory;

    // Deployed via factory
    Option public option;
    Rct public redemption;

    // Permit2
    IPermit2 public permit2 = IPermit2(PERMIT2);

    // Constants
    address public constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;
    uint160 public constant MAX160 = type(uint160).max;
    uint48 public constant MAX48 = type(uint48).max;
    uint256 public constant MAX256 = type(uint256).max;

    function setUp() public {
        // Fork Base
        vm.createSelectFork(vm.envOr("BASE_RPC_URL", string("https://mainnet.base.org")), 43189435);

        // Deploy test tokens
        stableToken = new StableToken();
        shakyToken = new ShakyToken();

        // Mint tokens to test contract
        stableToken.mint(address(this), 1_000_000 * 10 ** 18);
        shakyToken.mint(address(this), 1_000_000 * 10 ** 18);

        // Deploy template contracts (these will be cloned by factory)
        redemptionTemplate = new Rct("Short Template", "SHORT");

        optionTemplate = new Option("Long Template", "LONG");

        // Deploy Factory
        factory = new Factory(address(redemptionTemplate), address(optionTemplate));

        // Create an option pair via factory (required for testing Option/Collateral)
        CreateParams[] memory params = new CreateParams[](1);
        params[0] = CreateParams({
            collateral: address(shakyToken),
            consideration: address(stableToken),
            expirationDate: uint40(block.timestamp + 30 days),
            strike: uint96(1e18),
            isPut: false,
            isEuro: false,
            windowSeconds: 0
        });

        address optionAddress = factory.createOption(
            params[0].collateral, params[0].consideration, params[0].expirationDate, params[0].strike, params[0].isPut
        );

        // Get the deployed option and redemption
        option = Option(optionAddress);
        redemption = option.receipt();

        // Setup approvals for testing
        _setupApprovals();
    }

    function _setupApprovals() internal {
        // Approve Permit2
        IERC20(address(stableToken)).approve(address(factory), MAX256);
        IERC20(address(shakyToken)).approve(address(factory), MAX256);
        factory.approve(address(stableToken), MAX160);
        factory.approve(address(shakyToken), MAX160);

        // Approve factory via Permit2
        // permit2.approve(address(stableToken), address(factory), MAX160, MAX48);
        // permit2.approve(address(shakyToken), address(factory), MAX160, MAX48);
    }

    // ============================================
    // FACTORY GAS TESTS
    // ============================================

    function test_Gas_Factory_CreateOption() public {
        CreateParams[] memory params = new CreateParams[](1);
        params[0] = CreateParams({
            collateral: address(shakyToken),
            consideration: address(stableToken),
            expirationDate: uint40(block.timestamp + 60 days),
            strike: uint96(2e18),
            isPut: false,
            isEuro: false,
            windowSeconds: 0
        });

        factory.createOptions(params);
    }

    function test_Gas_Factory_CreateOption_DirectCall() public {
        factory.createOption(address(shakyToken), address(stableToken), uint40(block.timestamp + 60 days), 2e18, false);
    }

    function testFuzz_Gas_Factory_CreateMultipleOptions(uint8 count) public {
        count = uint8(bound(uint256(count), 1, 20));
        CreateParams[] memory params = new CreateParams[](count);

        for (uint256 i = 0; i < count; i++) {
            params[i] = CreateParams({
                collateral: address(shakyToken),
                consideration: address(stableToken),
                expirationDate: uint40(block.timestamp + 30 days + (i * 1 days)),
                strike: uint96(1e18 + (i * 0.1e18)),
                isPut: false,
                isEuro: false,
                windowSeconds: 0
            });
        }

        factory.createOptions(params);
    }

    // ============================================
    // OPTION GAS TESTS - CORE FUNCTIONS
    // ============================================

    function testFuzz_Gas_Option_Mint(uint256 amount) public {
        amount = bound(amount, 1, 1_000_000e18);
        option.mint(amount);
    }

    function test_Gas_Option_MintToAddress() public {
        // Need to fund the address first with collateral
        shakyToken.mint(address(0x123), 1000e18);

        vm.startPrank(address(0x123));
        IERC20(address(shakyToken)).approve(address(factory), MAX256);
        factory.approve(address(shakyToken), MAX160);
        // permit2.approve(address(shakyToken), address(factory), MAX160, MAX48);
        option.mint(address(0x123), 10);
        vm.stopPrank();
    }

    function testFuzz_Gas_Option_Exercise(uint256 mintAmt, uint256 exerciseAmt) public {
        mintAmt = bound(mintAmt, 1, 1_000e18);
        exerciseAmt = bound(exerciseAmt, 1, mintAmt);
        option.mint(mintAmt);
        option.exercise(exerciseAmt);
    }

    function testFuzz_Gas_Option_Redeem(uint256 mintAmt, uint256 redeemAmt) public {
        mintAmt = bound(mintAmt, 1, 1_000e18);
        redeemAmt = bound(redeemAmt, 1, mintAmt);
        option.mint(mintAmt);
        option.redeem(redeemAmt);
    }

    // ============================================
    // OPTION GAS TESTS - TRANSFERS
    // ============================================

    function test_Gas_Option_Transfer() public {
        option.mint(10);
        // forge-lint: disable-next-line(erc20-unchecked-transfer)
        IERC20(address(option)).transfer(address(0x123), 5);
    }

    function test_Gas_Option_Transfer_AutoMint() public {
        // Transfer more than balance triggers auto-mint (requires opt-in)
        factory.enableAutoMintRedeem(true);
        // forge-lint: disable-next-line(erc20-unchecked-transfer)
        IERC20(address(option)).transfer(address(0x123), 5);
    }

    function test_Gas_Option_TransferFrom() public {
        option.mint(10);
        option.approve(address(this), 10);
        // forge-lint: disable-next-line(erc20-unchecked-transfer)
        option.transferFrom(address(this), address(0x123), 5);
    }

    function test_Gas_Option_TransferFrom_AutoRedeem() public {
        option.mint(10);
        // forge-lint: disable-next-line(erc20-unchecked-transfer)
        IERC20(address(option)).transfer(address(0x123), 5);

        vm.prank(address(0x123));
        option.approve(address(this), 10);

        // TransferFrom back triggers auto-redeem
        // forge-lint: disable-next-line(erc20-unchecked-transfer)
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

    function test_Gas_Collateral_Mint() public {
        // Only callable by option contract
        vm.prank(address(option));
        redemption.mint(address(this), 10);
    }

    function test_Gas_Collateral_Exercise() public {
        option.mint(10);

        // Only callable by option contract
        vm.prank(address(option));
        redemption.exercise(address(this), 5, address(this));
    }

    function test_Gas_Collateral_Redeem_PreExpiration() public {
        option.mint(10);

        // Redeem via option contract's internal function before expiration
        vm.prank(address(option));
        redemption._redeemPair(address(this), 5);
    }

    function test_Gas_Collateral_Redeem_PostExpiration() public {
        option.mint(10);

        // Warp past expiration
        vm.warp(block.timestamp + 31 days);

        // Redeem directly after expiration
        redemption.redeem(5);
    }

    function test_Gas_Collateral_RedeemConsideration() public {
        option.mint(10);
        option.exercise(5);

        // Redeem using consideration tokens
        redemption.redeemConsideration(5);
    }

    function test_Gas_Collateral_Sweep_SingleUser() public {
        option.mint(10);

        // Warp past expiration
        vm.warp(block.timestamp + 31 days);

        // Sweep for single user
        redemption.sweep(address(this));
    }

    function test_Gas_Collateral_Sweep_MultipleUsers() public {
        option.mint(10);

        // Distribute to multiple users
        // forge-lint: disable-next-line(erc20-unchecked-transfer)
        IERC20(address(redemption)).transfer(address(0x123), 3);
        // forge-lint: disable-next-line(erc20-unchecked-transfer)
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

    function test_Gas_Collateral_Transfer() public {
        option.mint(10);
        // forge-lint: disable-next-line(erc20-unchecked-transfer)
        IERC20(address(redemption)).transfer(address(0x123), 5);
    }

    function test_Gas_Collateral_TransferFrom() public {
        option.mint(10);
        redemption.approve(address(this), 10);
        // forge-lint: disable-next-line(erc20-unchecked-transfer)
        redemption.transferFrom(address(this), address(0x123), 5);
    }

    function test_Gas_Collateral_Approve() public {
        redemption.approve(address(0x123), 100);
    }

    // ============================================
    // REDEMPTION GAS TESTS - VIEW FUNCTIONS
    // ============================================

    function test_Gas_Collateral_BalanceOf() public view {
        redemption.balanceOf(address(this));
    }

    function test_Gas_Collateral_BalancesOf() public {
        option.mint(10);
        option.balancesOf(address(this));
    }

    function test_Gas_Collateral_CollateralData() public view {
        redemption.collateralData();
    }

    function test_Gas_Collateral_ConsiderationData() public view {
        redemption.considerationData();
    }

    // ============================================
    // REDEMPTION GAS TESTS - ADMIN FUNCTIONS
    // ============================================

    function test_Gas_Collateral_Lock() public {
        // Only owner (Option contract) can lock
        vm.prank(address(option));
        redemption.lock();
    }

    function test_Gas_Collateral_Unlock() public {
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
        // forge-lint: disable-next-line(erc20-unchecked-transfer)
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
        // forge-lint: disable-next-line(erc20-unchecked-transfer)
        IERC20(address(option)).transfer(address(0x123), 50);

        // User 2 exercises
        stableToken.mint(address(0x123), 1000e18);
        vm.startPrank(address(0x123));
        IERC20(address(stableToken)).approve(address(factory), MAX256);
        factory.approve(address(stableToken), MAX160);
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
}
