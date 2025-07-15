// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../contracts/AddressSet.sol";

contract GasComparisonTest is Test {
    // Library approach (simulated)
    struct LibrarySet {
        mapping(address => uint256) location;
        address[] list;
    }
    
    LibrarySet private librarySet;
    
    // Contract approach
    AddressSet public addressSet;
    
    // Advanced approach
    
    function setUp() public {
        addressSet = new AddressSet();
    }
    
    function testGasComparison() public {
        address[] memory testAddresses = new address[](1000);
        for (uint256 i = 0; i < 1000; i++) {
            testAddresses[i] = address(uint160(i + 1));
        }
        
        uint256 gasUsed;
        
        // Test Library approach (simulated)
        gasUsed = gasleft();
        for (uint256 i = 0; i < 1000; i++) {
            addToLibrarySet(testAddresses[i]);
        }
        uint256 libraryGas = gasUsed - gasleft();
        
        // Test Contract approach (optimized)
        gasUsed = gasleft();
        for (uint256 i = 0; i < 1000; i++) {
            addressSet.add(testAddresses[i]);
        }
        uint256 contractGas = gasUsed - gasleft();
        
        console.log("Library approach:", libraryGas);
        console.log("Optimized Contract approach:", contractGas);
        
        // Library should still be most efficient, but gap should be smaller
        assertTrue(libraryGas < contractGas, "Library should be more gas efficient than contract");
    }
    
    function testRemoveCapability() public {
        // Add some addresses first
        address[] memory testAddresses = new address[](10);
        for (uint256 i = 0; i < 10; i++) {
            testAddresses[i] = address(uint160(i + 1));
            addressSet.add(testAddresses[i]);
        }
        
        // Verify all addresses are added
        assertEq(addressSet.length(), 10, "Should have 10 addresses");
        assertTrue(addressSet.contains(testAddresses[0]), "Should contain first address");
        assertTrue(addressSet.contains(testAddresses[5]), "Should contain middle address");
        assertTrue(addressSet.contains(testAddresses[9]), "Should contain last address");
        
        // Test individual removal
        console.log("Testing individual removal...");
        
        // Remove first address
        assertTrue(addressSet.remove(testAddresses[0]), "Should successfully remove first address");
        assertEq(addressSet.length(), 9, "Length should be 9 after removal");
        assertFalse(addressSet.contains(testAddresses[0]), "Should not contain removed address");
        assertTrue(addressSet.contains(testAddresses[1]), "Should still contain other addresses");
        
        // Remove middle address
        assertTrue(addressSet.remove(testAddresses[5]), "Should successfully remove middle address");
        assertEq(addressSet.length(), 8, "Length should be 8 after second removal");
        assertFalse(addressSet.contains(testAddresses[5]), "Should not contain removed middle address");
        
        // Remove last address
        assertTrue(addressSet.remove(testAddresses[9]), "Should successfully remove last address");
        assertEq(addressSet.length(), 7, "Length should be 7 after third removal");
        assertFalse(addressSet.contains(testAddresses[9]), "Should not contain removed last address");
        
        // Test removing non-existent address
        assertFalse(addressSet.remove(address(0x999)), "Should return false for non-existent address");
        assertEq(addressSet.length(), 7, "Length should remain 7");
        
        // Test removing already removed address
        assertFalse(addressSet.remove(testAddresses[0]), "Should return false for already removed address");
        assertEq(addressSet.length(), 7, "Length should remain 7");
        
        console.log("Individual removal tests passed!");
        
        // Test clear functionality
        console.log("Testing clear functionality...");
        addressSet.clear();
        assertEq(addressSet.length(), 0, "Length should be 0 after clear");
        assertTrue(addressSet.isEmpty(), "Should be empty after clear");
        
        // Verify no addresses remain
        for (uint256 i = 0; i < 10; i++) {
            assertFalse(addressSet.contains(testAddresses[i]), "Should not contain any address after clear");
        }
        
        console.log("Clear functionality test passed!");
    }
    
    function testRemoveGasEfficiency() public {
        // Add 100 addresses
        uint256 gasUsed;
        address[] memory testAddresses = new address[](100);
        for (uint256 i = 0; i < 99; i++) {
            testAddresses[i] = address(uint160(i + 1));
            addressSet.add(testAddresses[i]);
        }

        // add the last address
        gasUsed = gasleft();
        testAddresses[99] = address(uint160(100));
        addressSet.add(testAddresses[99]);
        uint256 addOneMoreGas = gasUsed - gasleft();
        
        assertEq(addressSet.length(), 100, "Should have 100 addresses");
        
        
        // Test gas efficiency of removal from different positions
        console.log("Testing removal gas efficiency...");
        
        // Remove from beginning
        gasUsed = gasleft();
        addressSet.remove(testAddresses[0]);
        uint256 removeFirstGas = gasUsed - gasleft();
        
        // Remove from middle
        gasUsed = gasleft();
        addressSet.remove(testAddresses[50]);
        uint256 removeMiddleGas = gasUsed - gasleft();
        
        // Remove from end
        gasUsed = gasleft();
        addressSet.remove(testAddresses[98]); // Note: index 99 is now at position 98 after previous removals
        uint256 removeLastGas = gasUsed - gasleft();


        gasUsed = gasleft();
        assertTrue(addressSet.contains(testAddresses[1]), "Should still contain address[1]");
        uint256 containsFirstGas = gasUsed - gasleft();

        // check if address[98] is still in the set
        
        console.log("Gas used for removals:");
        console.log("Remove first element:", removeFirstGas);
        console.log("Remove middle element:", removeMiddleGas);
        console.log("Remove last element:", removeLastGas);
        console.log("Contains first element:", containsFirstGas);
        console.log("Add one more element:", addOneMoreGas);
    }
    
    function testSingleAddGas() public {
        uint256 gasUsed;
        
        // Test single add operation
        gasUsed = gasleft();
        addressSet.add(address(0x123));
        uint256 addGas = gasUsed - gasleft();
        
        console.log("Gas for single add operation:", addGas);
        
        
        // Test contains operation
        gasUsed = gasleft();
        bool contains = addressSet.contains(address(0x123));
        uint256 containsGas = gasUsed - gasleft();
        
        console.log("Gas for contains operation:", containsGas);
        
        // Test remove operation
        gasUsed = gasleft();
        bool removed = addressSet.remove(address(0x123));
        uint256 removeGas = gasUsed - gasleft();
        
        console.log("Gas for remove operation:", removeGas);
    }
    
    // Helper function to simulate library approach
    function addToLibrarySet(address value) private returns (bool) {
        if (librarySet.location[value] == 0) {
            librarySet.list.push(value);
            librarySet.location[value] = librarySet.list.length;
            return true;
        }
        return false;
    }
} 