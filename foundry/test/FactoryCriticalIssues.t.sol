//// SPDX-License-Identifier: MIT
//pragma solidity ^0.8.30;
//
//import "forge-std/Test.sol";
//import "../contracts/OptionFactory.sol";
//
///**
// * @title Factory Critical Issues Test
// * @notice Demonstrates CRITICAL vulnerabilities in new functions
// */
//contract FactoryCriticalIssuesTest is Test {
//    OptionFactory factory;
//    address owner = address(this);
//    address user = address(0x1234);
//
//    function setUp() public {
//        MockContract redemptionTemplate = new MockContract();
//        MockContract optionTemplate = new MockContract();
//
//        factory = new OptionFactory(
//            address(redemptionTemplate),
//            address(optionTemplate),
//            0.001e18 // 0.1% initial fee
//        );
//    }
//
//    /**
//     *  FIXED: adjustFee() NOW has maximum limit validation
//     * Verifies that fees cannot exceed MAX_FEE
//     */
//    function testFIXED_AdjustFeeHasLimit() public {
//        console.log("Initial fee:", factory.fee());
//        console.log("MAX_FEE:", factory.MAX_FEE());
//
//        // Try to set fee above maximum - should REVERT
//        vm.expectRevert("fee exceeds maximum");
//        factory.adjustFee(1e18); // 100% - above MAX_FEE
//
//        // Can set fee TO maximum (1%)
//        factory.adjustFee(uint64(factory.MAX_FEE()));
//        assertEq(factory.fee(), factory.MAX_FEE());
//        console.log("Fee set to MAX_FEE:", factory.fee());
//
//        // Cannot set fee ABOVE maximum (2%)
//        vm.expectRevert("fee exceeds maximum");
//        factory.adjustFee(0.02e18); // 2% - above 1% limit
//
//        console.log("");
//        console.log("FIXED: adjustFee() now enforces MAX_FEE limit!");
//    }
//
//    /**
//     * Verify that fee cannot be set to enable rug-pull
//     */
//    function testFIXED_FeeCannotRugPull() public {
//        // Cannot set fee to 100%
//        vm.expectRevert("fee exceeds maximum");
//        factory.adjustFee(1e18); // 100% fee - REVERTS
//
//        // Verify fee is still at original value
//        assertEq(factory.fee(), 0.001e18);
//
//        console.log("");
//        console.log("FIXED: Cannot set fee high enough for rug-pull!");
//    }
//
//    /**
//     *  CRITICAL-NEW-02: adjustTemplates() allows malicious template swap
//     * Owner can silently swap to backdoored contracts
//     */
//    function testCRITICAL_AdjustTemplatesRugPull() public {
//        address originalRedemption = factory.redemptionClone();
//        address originalOption = factory.optionClone();
//
//        console.log("Original redemption template:", originalRedemption);
//        console.log("Original option template:", originalOption);
//
//        // Owner creates malicious templates
//        MaliciousRedemption maliciousRedemption = new MaliciousRedemption();
//        MaliciousOption maliciousOption = new MaliciousOption();
//
//        // Owner silently swaps templates - NO TIMELOCK, NO WARNING!
//        factory.adjustTemplates(address(maliciousOption), address(maliciousRedemption));
//
//        assertEq(factory.optionClone(), address(maliciousOption));
//        assertEq(factory.redemptionClone(), address(maliciousRedemption));
//
//        console.log("New redemption template:", factory.redemptionClone());
//        console.log("New option template:", factory.optionClone());
//        console.log("");
//        console.log(" CRITICAL: Templates swapped to malicious contracts!");
//        console.log(" All future options will use attacker's code!");
//        console.log(" Attacker can steal all deposited collateral!");
//    }
//
//    /**
//     *  CRITICAL-NEW-02: No events emitted for template changes
//     * Users have NO WARNING that templates changed
//     */
//    function testCRITICAL_AdjustTemplatesNoEvent() public {
//        MaliciousRedemption maliciousRedemption = new MaliciousRedemption();
//        MaliciousOption maliciousOption = new MaliciousOption();
//
//        // Record logs before
//        vm.recordLogs();
//
//        // Swap templates
//        factory.adjustTemplates(address(maliciousOption), address(maliciousRedemption));
//
//        // Check logs
//        Vm.Log[] memory logs = vm.getRecordedLogs();
//
//        // NO EVENTS EMITTED!
//        assertEq(logs.length, 0, "Should emit event but doesn't!");
//
//        console.log("");
//        console.log(" CRITICAL: Template swap is SILENT!");
//        console.log(" Users have NO WAY to detect malicious templates!");
//    }
//
//    /**
//     * Demonstrate attack scenario
//     */
//    function testCRITICAL_CompleteAttackScenario() public {
//        console.log("=== COMPLETE ATTACK SCENARIO ===");
//        console.log("");
//        console.log("Step 1: Protocol launches successfully");
//        console.log("- Users trust the protocol");
//        console.log("- TVL grows to $10M");
//        console.log("");
//
//        console.log("Step 2: Owner creates malicious templates");
//        MaliciousRedemption maliciousRedemption = new MaliciousRedemption();
//        MaliciousOption maliciousOption = new MaliciousOption();
//        console.log("- Malicious contracts have backdoor");
//        console.log("");
//
//        console.log("Step 3: Owner silently swaps templates (NO WARNING)");
//        factory.adjustTemplates(address(maliciousOption), address(maliciousRedemption));
//        console.log("- Templates swapped");
//        console.log("- No events emitted");
//        console.log("- Users don't know");
//        console.log("");
//
//        console.log("Step 4: Users create new options");
//        console.log("- Users deposit collateral");
//        console.log("- Malicious code executes");
//        console.log("- Collateral sent to attacker");
//        console.log("");
//
//        console.log("Step 5: Attacker profits");
//        console.log("- All new deposits stolen");
//        console.log("- Protocol reputation destroyed");
//        console.log("- Users lose funds");
//        console.log("");
//
//        console.log(" THIS IS A COMPLETE RUG-PULL VECTOR ");
//    }
//}
//
///**
// * Mock malicious redemption contract
// * In reality, this would have backdoors to steal funds
// */
//contract MaliciousRedemption {
//    // Malicious code would go here
//    // For example: send all collateral to attacker
//    address public attacker;
//
//    constructor() {
//        attacker = msg.sender;
//    }
//
//    function init(
//        address, // collateral
//        address, // consideration
//        uint40, // expirationDate
//        uint256, // strike
//        bool, // isPut
//        address, // option
//        address, // factory
//        uint64 // fee
//    ) public {
//        // Malicious init - could do anything
//    }
//}
//
///**
// * Mock malicious option contract
// */
//contract MaliciousOption {
//    address public attacker;
//
//    constructor() {
//        attacker = msg.sender;
//    }
//
//    function init(address, address, uint64) public {
//        // Malicious init
//    }
//}
//
///**
// * Mock contract for testing
// */
//contract MockContract {
//    function init(address, address, uint40, uint256, bool, address, address, uint64) public { }
//}
