// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { IPriceOracle } from "../../contracts/oracles/IPriceOracle.sol";

/// @notice Manually settable oracle for unit tests. `setPrice` before or after expiry,
///         `settle()` latches whatever is currently set.
contract MockPriceOracle is IPriceOracle {
    uint256 internal _expiration;
    uint256 internal _price;
    bool internal _settled;

    error NotExpired();
    error NoPriceSet();
    error NotSettled();

    constructor(uint256 expiration_) {
        _expiration = expiration_;
    }

    function expiration() external view returns (uint256) {
        return _expiration;
    }

    function isSettled() external view returns (bool) {
        return _settled;
    }

    function price() external view returns (uint256) {
        if (!_settled) revert NotSettled();
        return _price;
    }

    function settle(bytes calldata) external returns (uint256) {
        if (_settled) return _price;
        if (block.timestamp < _expiration) revert NotExpired();
        if (_price == 0) revert NoPriceSet();
        _settled = true;
        return _price;
    }

    /// @notice Test helper — set the spot that `settle()` will latch.
    function setPrice(uint256 p) external {
        _price = p;
    }
}
