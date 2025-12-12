// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title AddressSet
 * @dev Library for managing sets of addresses with efficient lookup, insertion, and removal.
 * Similar to OpenZeppelin's EnumerableSet but optimized for gas efficiency.
 *
 * Usage:
 *   using AddressSet for AddressSet.Set;
 *   AddressSet.Set private mySet;
 */
library AddressSet {
    struct Set {
        // Storage layout optimized for minimal overhead
        mapping(address => uint256) _indices; // 1-based index, 0 = not present
        address[] _values;
        uint256 _length; // Cached length to avoid array access
    }

    /**
     * @dev Add a value to the set. O(1).
     * Returns true if the value was added (wasn't already present).
     */
    function add(Set storage set, address value) internal returns (bool) {
        if (set._indices[value] == 0) {
            set._values.push(value);
            set._indices[value] = set._length + 1; // 1-based indexing
            set._length++;
            return true;
        }
        return false;
    }

    /**
     * @dev Remove a value from the set. O(1).
     * Returns true if the value was removed (was present).
     */
    function remove(Set storage set, address value) internal returns (bool) {
        uint256 index = set._indices[value];
        if (index == 0) return false;

        uint256 idx = index - 1;
        uint256 last = set._length - 1;

        // Swap with last element if not already last
        if (idx != last) {
            address lastValue = set._values[last];
            set._values[idx] = lastValue;
            set._indices[lastValue] = idx + 1;
        }

        // Remove last element
        set._values.pop();
        set._length--;
        delete set._indices[value];
        return true;
    }

    /**
     * @dev Check if a value exists in the set. O(1).
     */
    function contains(Set storage set, address value) internal view returns (bool) {
        return set._indices[value] != 0;
    }

    /**
     * @dev Get the number of elements in the set. O(1).
     */
    function length(Set storage set) internal view returns (uint256) {
        return set._length;
    }

    /**
     * @dev Check if the set is empty. O(1).
     */
    function isEmpty(Set storage set) internal view returns (bool) {
        return set._length == 0;
    }

    /**
     * @dev Get the value at a given index. O(1).
     * Reverts if index is out of bounds.
     */
    function at(Set storage set, uint256 index) internal view returns (address) {
        require(index < set._length, "AddressSet: index out of bounds");
        return set._values[index];
    }

    /**
     * @dev Return the entire set as an array. O(n).
     * WARNING: This can be expensive for large sets.
     */
    function values(Set storage set) internal view returns (address[] memory) {
        return set._values;
    }

    /**
     * @dev Remove all values from the set. O(n).
     * WARNING: This can be expensive for large sets.
     */
    function clear(Set storage set) internal {
        uint256 len = set._length;
        for (uint256 i = 0; i < len; i++) {
            delete set._indices[set._values[i]];
        }
        delete set._values;
        set._length = 0;
    }
}
