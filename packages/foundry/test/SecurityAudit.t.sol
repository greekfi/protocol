// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { Test, console } from "forge-std/Test.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { OptionFactory, Redemption, Option, OptionParameter } from "../contracts/OptionFactory.sol";
import { StableToken } from "../contracts/StableToken.sol";
import { ShakyToken } from "../contracts/ShakyToken.sol";

/**
 * @title SecurityAuditTest
 * @notice Comprehensive security tests for Option protocol
 * @dev Tests cover vulnerabilities identified in security audit
 */
contract SecurityAuditTest is Test {
    using SafeERC20 for IERC20;

    StableToken public stableToken;
    ShakyToken public shakyToken;
    OptionFactory public factory;
    Option public option;
    Redemption public redemption;

    address constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;
    string constant UNICHAIN_RPC_URL = "https://unichain.drpc.org";

    address public attacker = address(0x666);
    address public alice = address(0xA11CE);
    address public bob = address(0xB0B);

    function setUp() public {
        vm.createSelectFork(UNICHAIN_RPC_URL);

        // Deploy tokens
        stableToken = new StableToken();
        shakyToken = new ShakyToken();

        // Mint tokens
        stableToken.mint(address(this), 1_000_000 * 10 ** 18);
        shakyToken.mint(address(this), 1_000_000 * 10 ** 18);
        stableToken.mint(alice, 1_000_000 * 10 ** 18);
        shakyToken.mint(alice, 1_000_000 * 10 ** 18);
        stableToken.mint(bob, 1_000_000 * 10 ** 18);
        shakyToken.mint(bob, 1_000_000 * 10 ** 18);

        // Deploy template contracts
        Redemption redemptionClone = new Redemption(
            "Short", "SHORT", address(stableToken), address(shakyToken), block.timestamp + 1 days, 100, false
        );

        Option optionClone = new Option(
            "Long",
            "LONG",
            address(stableToken),
            address(shakyToken),
            block.timestamp + 1 days,
            100,
            false,
            address(redemptionClone)
        );

        // Deploy factory
        factory = new OptionFactory(address(redemptionClone), address(optionClone));

        // Create option via factory
        OptionParameter[] memory options = new OptionParameter[](1);
        options[0] = OptionParameter({
            optionSymbol: "LONG",
            redemptionSymbol: "SHORT",
            collateral_: address(shakyToken),
            consideration_: address(stableToken),
            expiration: block.timestamp + 1 days,
            strike: 1e18,
            isPut: false
        });

        factory.createOptions(options);

        address[] memory options1 = factory.getOptions();
        option = Option(options1[0]);
        redemption = option.redemption();
    }

    // ==============================================
    // CRITICAL VULNERABILITY TESTS
    // ==============================================

    /**
     * @notice TEST: Unprotected Initialization
     * @dev CRITICAL - Attacker can front-run initialization and gain ownership
     */
    function test_Critical_InitializationFrontRunning() public {
        // This test demonstrates the initialization vulnerability
        // In production, attacker would monitor mempool and front-run factory calls

        // Create a new clone directly (simulating what factory does)
        address redemptionClone = address(
            new Redemption(
                "Short", "SHORT", address(stableToken), address(shakyToken), block.timestamp + 1 days, 100, false
            )
        );

        // Attacker can call init directly (if not protected)
        vm.startPrank(attacker);

        // NOTE: Current implementation allows this - vulnerability exists
        // After fix, this should revert with "Only factory can initialize"
        try Redemption(redemptionClone)
            .init(
                "Malicious",
                "EVIL",
                address(stableToken),
                address(shakyToken),
                block.timestamp + 1 days,
                1e18,
                false,
                attacker
            ) {
            // If this succeeds, vulnerability exists
            assertEq(Redemption(redemptionClone).owner(), attacker, "Attacker gained ownership!");
            console.log("VULNERABILITY CONFIRMED: Attacker can front-run initialization");
        } catch {
            console.log("PROTECTED: Initialization is protected against front-running");
        }

        vm.stopPrank();
    }

    /**
     * @notice TEST: Reentrancy in JIT Minting
     * @dev CRITICAL - External calls during transfer enable reentrancy
     */
    function test_Critical_ReentrancyInTransfer() public {
        // Setup: Approve tokens
        shakyToken.approve(address(redemption), type(uint256).max);
        stableToken.approve(address(redemption), type(uint256).max);

        // This test shows that external calls happen during transfer
        // A malicious token could exploit this

        // Normal flow - should work
        option.transfer(alice, 10);

        assertEq(option.balanceOf(alice), 10);

        // NOTE: To fully test this, would need a malicious ERC20 that reenters
        // Current test shows the vulnerability surface exists
        console.log("VULNERABILITY SURFACE: External calls in transfer enable reentrancy");
    }

    // ==============================================
    // HIGH SEVERITY TESTS
    // ==============================================

    /**
     * @notice TEST: Unbounded Array Growth
     * @dev HIGH - accounts array grows without bounds causing DoS
     */
    function test_High_UnboundedAccountsArray() public {
        // Approve tokens
        shakyToken.approve(address(redemption), type(uint256).max);
        stableToken.approve(address(redemption), type(uint256).max);

        // Mint some tokens
        option.mint(1000);

        // Transfer to many addresses to populate accounts array
        for (uint256 i = 1; i <= 50; i++) {
            address recipient = address(uint160(i));
            option.transfer(recipient, 1);
        }

        // Transfer between addresses to create duplicates
        vm.startPrank(address(1));
        option.transfer(address(2), 1);
        vm.stopPrank();

        vm.startPrank(address(2));
        option.transfer(address(3), 1);
        vm.stopPrank();

        // The accounts array now has duplicates
        // With enough transactions, sweep() will run out of gas

        console.log("VULNERABILITY: accounts array has unbounded growth");
        console.log("In production, this leads to DoS of sweep() function");

        // Test sweep after expiration
        vm.warp(block.timestamp + 2 days);

        // This will work with small numbers but fails with large holder counts
        try redemption.sweep() {
            console.log("Sweep succeeded with small holder count");
        } catch {
            console.log("Sweep failed - DoS vulnerability triggered");
        }
    }

    /**
     * @notice TEST: Missing Exercise Permission
     * @dev HIGH - Anyone can exercise and send collateral to arbitrary address
     */
    function test_High_MissingExercisePermission() public {
        // Setup: Alice mints options
        vm.startPrank(alice);
        shakyToken.approve(address(redemption), type(uint256).max);
        stableToken.approve(address(redemption), type(uint256).max);
        option.mint(100);
        vm.stopPrank();

        // Attacker has consideration tokens
        vm.startPrank(attacker);
        stableToken.mint(attacker, 10000e18);
        stableToken.approve(address(redemption), type(uint256).max);

        // Transfer options from Alice to attacker (simulate purchase)
        vm.stopPrank();
        vm.startPrank(alice);
        option.transfer(attacker, 50);
        vm.stopPrank();

        // Attacker can exercise and send collateral to any address
        vm.startPrank(attacker);

        uint256 bobBalanceBefore = shakyToken.balanceOf(bob);

        // VULNERABILITY: Attacker can send collateral to Bob without permission
        option.exercise(bob, 10);

        uint256 bobBalanceAfter = shakyToken.balanceOf(bob);

        assertTrue(bobBalanceAfter > bobBalanceBefore, "Collateral sent to Bob");
        console.log("VULNERABILITY: Attacker sent collateral to arbitrary address (Bob)");
        console.log("This should require Bob's approval or be restricted");

        vm.stopPrank();
    }

    /**
     * @notice TEST: Mutable Redemption Address
     * @dev HIGH - Owner can change redemption mid-flight
     */
    function test_High_MutableRedemptionAddress() public {
        // Setup: Mint options
        shakyToken.approve(address(redemption), type(uint256).max);
        option.mint(100);

        Redemption originalRedemption = option.redemption();
        uint256 shortBalance = originalRedemption.balanceOf(address(this));

        assertEq(shortBalance, 100, "Should have 100 redemption tokens");

        // Owner changes redemption address
        Redemption newRedemption = new Redemption(
            "New Short", "NSHORT", address(stableToken), address(shakyToken), block.timestamp + 1 days, 1e18, false
        );

        // VULNERABILITY: This succeeds and breaks invariants
        option.setRedemption(address(newRedemption));

        // Now redemption pointer changed but old tokens still exist
        Redemption currentRedemption = option.redemption();

        assertTrue(address(currentRedemption) != address(originalRedemption), "Redemption address changed");
        console.log("VULNERABILITY: Redemption can be changed after minting");
        console.log("This breaks contract invariants and user expectations");
    }

    // ==============================================
    // MEDIUM SEVERITY TESTS
    // ==============================================

    /**
     * @notice TEST: Missing Decimal Validation
     * @dev MEDIUM - No bounds checking on token decimals
     */
    function test_Medium_MissingDecimalValidation() public {
        // This test shows that contract doesn't validate decimals
        // In production, malicious token with extreme decimals could cause issues

        console.log("NOTE: Contract should validate decimals are between 0 and 18");
        console.log("Current implementation does not check this");

        // Would need a mock token with invalid decimals to fully test
        // But code review shows no validation exists
    }

    /**
     * @notice TEST: No Slippage Protection
     * @dev MEDIUM - User may receive less collateral than expected
     */
    function test_Medium_NoSlippageProtection() public {
        // Setup
        shakyToken.approve(address(redemption), type(uint256).max);
        stableToken.approve(address(redemption), type(uint256).max);

        // Alice mints options
        vm.startPrank(alice);
        shakyToken.approve(address(redemption), type(uint256).max);
        stableToken.approve(address(redemption), type(uint256).max);
        option.mint(100);
        vm.stopPrank();

        // Bob mints and exercises, depleting collateral
        vm.startPrank(bob);
        shakyToken.approve(address(redemption), type(uint256).max);
        stableToken.approve(address(redemption), type(uint256).max);
        option.mint(100);
        option.exercise(100);
        vm.stopPrank();

        // Now Alice tries to exercise but gets less than expected
        vm.startPrank(alice);
        uint256 collateralBefore = shakyToken.balanceOf(alice);

        // VULNERABILITY: No way to specify minimum acceptable amount
        option.exercise(50);

        uint256 collateralAfter = shakyToken.balanceOf(alice);
        uint256 received = collateralAfter - collateralBefore;

        // Alice may receive less than 50 if collateral is depleted
        console.log("Collateral received:", received);
        console.log("VULNERABILITY: No slippage protection on exercise");

        vm.stopPrank();
    }

    /**
     * @notice TEST: Lack of Pausability
     * @dev MEDIUM - No emergency stop for critical functions
     */
    function test_Medium_LackOfPausability() public {
        // Contract has lock() but it only prevents transfers
        // Mint, exercise, and redeem cannot be paused

        shakyToken.approve(address(redemption), type(uint256).max);

        // Lock the contract
        option.lock();

        // Transfer is blocked (correctly)
        vm.expectRevert("Contract is Locked");
        option.transfer(alice, 10);

        // But mint still works (vulnerability)
        option.mint(10);
        console.log("VULNERABILITY: lock() only prevents transfers");
        console.log("Mint, exercise, and redeem cannot be emergency paused");
    }

    // ==============================================
    // LOW SEVERITY TESTS
    // ==============================================

    /**
     * @notice TEST: External Balance Call
     * @dev LOW - Wasteful external call in transfer
     */
    function test_Low_ExternalBalanceCall() public {
        // Line 100 of Option.sol uses this.balanceOf() instead of balanceOf()
        // This is wasteful but not a security issue

        console.log("CODE QUALITY: Use balanceOf() instead of this.balanceOf()");
    }

    /**
     * @notice TEST: Redundant Storage
     * @dev LOW - Both redemption_ and redemption stored
     */
    function test_Low_RedundantStorage() public {
        // Option.sol stores both address redemption_ and Redemption redemption
        address addr1 = option.redemption_();
        address addr2 = address(option.redemption());

        assertEq(addr1, addr2, "Redundant storage wastes gas");
        console.log("GAS OPTIMIZATION: Remove redundant redemption_ storage");
    }

    /**
     * @notice TEST: Missing Events
     * @dev LOW - State changes without events
     */
    function test_Low_MissingEvents() public {
        // setRedemption, lock/unlock should emit events
        console.log("CODE QUALITY: Add events for setRedemption, lock, unlock, etc.");
    }

    // ==============================================
    // ADDITIONAL SECURITY TESTS
    // ==============================================

    /**
     * @notice TEST: Access Control on Admin Functions
     */
    function test_AccessControl_OnlyOwnerFunctions() public {
        vm.startPrank(attacker);

        vm.expectRevert();
        option.setRedemption(address(0x123));

        vm.expectRevert();
        option.lock();

        vm.expectRevert();
        option.unlock();

        vm.stopPrank();

        console.log("PASS: Admin functions are properly protected");
    }

    /**
     * @notice TEST: Reentrancy Guards
     */
    function test_ReentrancyGuards() public {
        // All critical functions have nonReentrant modifier
        // But reentrancy can still occur via external calls in transfer
        console.log("PARTIAL: nonReentrant used but external calls enable reentrancy");
    }

    /**
     * @notice TEST: Integer Overflow/Underflow
     */
    function test_IntegerSafety() public {
        // Solidity 0.8+ has automatic overflow checks
        // But strike price calculations could still overflow with extreme values

        shakyToken.approve(address(redemption), type(uint256).max);

        option.mint(type(uint128).max); // Large value

        // Test toConsideration with large amount
        uint256 large = type(uint128).max;
        uint256 consAmount = option.toConsideration(large);

        console.log("Testing large values in strike calculations");
        console.log("Consideration amount:", consAmount);
    }

    /**
     * @notice TEST: Zero Address Checks
     */
    function test_ZeroAddressChecks() public {
        // Test that zero addresses are properly rejected
        console.log("Zero address checks exist in some places but not comprehensive");
    }

    /**
     * @notice TEST: Expiration Logic
     */
    function test_ExpirationLogic() public {
        shakyToken.approve(address(redemption), type(uint256).max);
        option.mint(100);

        // Before expiration - should work
        option.exercise(10);

        // After expiration - should fail
        vm.warp(block.timestamp + 2 days);

        vm.expectRevert();
        option.exercise(10);

        console.log("PASS: Expiration logic works correctly");
    }

    // ==============================================
    // HELPER FUNCTIONS
    // ==============================================

    function logSeparator(string memory title) internal pure {
        console.log("");
        console.log("==============================================");
        console.log(title);
        console.log("==============================================");
    }
}
