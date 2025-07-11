// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

library AddressSet {
    struct Set {
        mapping(address => uint256) location; // 1-based index
        address[] list;
    }

    function add(Set storage self, address value) internal returns (bool) {
        if (self.location[value] == 0) {
            self.list.push(value);
            self.location[value] = self.list.length; // 1-based
            return true;
        }
        return false;
    }

    function remove(Set storage self, address value) internal returns (bool) {
        uint256 index = self.location[value];
        if (index == 0) return false;

        uint256 idx = index - 1;
        uint256 last = self.list.length - 1;

        if (idx != last) {
            address lastValue = self.list[last];
            self.list[idx] = lastValue;
            self.location[lastValue] = idx + 1;
        }

        self.list.pop();
        delete self.location[value];
        return true;
    }

    function contains(Set storage self, address value) internal view returns (bool) {
        return self.location[value] != 0;
    }

    function values(Set storage self) internal view returns (address[] memory) {
        return self.list;
    }

    function length(Set storage self) internal view returns (uint256) {
        return self.list.length;
    }
}