// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

import "forge-std/Test.sol";
import "../contracts/OptionFactory.sol";

/**
 * @title Factory Security Test
 * @notice Demonstrates critical vulnerabilities found in OptionFactory security audit
 */
contract FactorySecurityTest is Test {
    OptionFactory factory;
    address redemptionTemplate;
    address optionTemplate;

    address owner = address(this);

    // Mock ERC20 for testing
    MockERC20 collateralToken;
    MockERC20 considerationToken;

    function setUp() public {
        // For this test, we'll use mock addresses for templates
        // In reality, you'd deploy actual templates
        redemptionTemplate = address(new MockContract());
        optionTemplate = address(new MockContract());

        // Deploy factory with 0.1% fee
        factory = new OptionFactory(redemptionTemplate, optionTemplate, 0.001e18);

        // Deploy mock tokens
        collateralToken = new MockERC20("Collateral", "COLL", 18);
        considerationToken = new MockERC20("Consideration", "CONS", 18);
    }

    /**
     * HIGH-01: Template validation - NOW FIXED (both zero)
     * This test verifies factory now rejects zero address templates
     */
    function testFIXED_TemplateValidation_BothZero() public {
        // Now REVERTS when deployed with zero addresses
        vm.expectRevert(OptionFactory.InvalidAddress.selector);
        new OptionFactory(
            address(0), // Invalid redemption template
            address(0), // Invalid option template
            0.001e18
        );

        console.log("FIXED: Constructor rejects both zero addresses!");
    }

    /**
     * HIGH-01: Template validation - NOW FIXED (one zero)
     * This test verifies factory rejects if either template is zero
     */
    function testFIXED_TemplateValidation_OneZero() public {
        // Create valid template first
        address validTemplate = address(new MockContract());

        // Reverts with only redemption as zero
        vm.expectRevert(OptionFactory.InvalidAddress.selector);
        new OptionFactory(
            address(0), // Invalid redemption template
            validTemplate, // Valid option template
            0.001e18
        );

        console.log("FIXED: Constructor rejects redemption zero address!");
    }

    /**
     * HIGH-01: Template validation - NOW FIXED (option zero)
     * This test verifies factory rejects if option template is zero
     */
    function testFIXED_TemplateValidation_OptionZero() public {
        // Create valid template first
        address validTemplate = address(new MockContract());

        // Reverts with only option as zero
        vm.expectRevert(OptionFactory.InvalidAddress.selector);
        new OptionFactory(
            validTemplate, // Valid redemption
            address(0), // Invalid option template
            0.001e18
        );

        console.log("FIXED: Constructor rejects option zero address!");
    }

    /**
     * LOW-01: unblockToken missing zero-address check
     */
    function testLOW_UnblockTokenNoValidation() public {
        // Can unblock zero address (should fail but doesn't)
        vm.expectRevert(OptionFactory.InvalidAddress.selector);
        factory.unblockToken(address(0));

        // No error, no event (if we checked blocklist[address(0)] it's now false)
        assertFalse(factory.blocklist(address(0)));
        console.log("LOW SEVERITY: Can unblock zero address");
    }

    /**
     * Test that demonstrates blocklist basic functionality
     */
    function testCorrectBehavior_BlocklistWorks() public {
        // Block a token
        factory.blockToken(address(collateralToken));
        assertTrue(factory.isBlocked(address(collateralToken)));

        // Unblock token
        factory.unblockToken(address(collateralToken));
        assertFalse(factory.isBlocked(address(collateralToken)));

        console.log("Blocklist basic functionality works");
    }
}

/**
 * Mock contract for testing
 */
contract MockContract {
    // Empty contract to use as template address

    }

/**
 * Mock ERC20 token for testing
 */
contract MockERC20 {
    string public name;
    string public symbol;
    uint8 public decimals;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    uint256 public totalSupply;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    constructor(string memory _name, string memory _symbol, uint8 _decimals) {
        name = _name;
        symbol = _symbol;
        decimals = _decimals;
    }

    function mint(address to, uint256 amount) public {
        balanceOf[to] += amount;
        totalSupply += amount;
        emit Transfer(address(0), to, amount);
    }

    function transfer(address to, uint256 amount) public returns (bool) {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        emit Transfer(msg.sender, to, amount);
        return true;
    }

    function approve(address spender, uint256 amount) public returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) public returns (bool) {
        require(allowance[from][msg.sender] >= amount, "insufficient allowance");
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        emit Transfer(from, to, amount);
        return true;
    }
}
