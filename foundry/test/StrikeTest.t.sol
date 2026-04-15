// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { Test, console } from "forge-std/Test.sol";
import { OptionUtils } from "../contracts/OptionUtils.sol";

contract StrikeTest is Test {
    function _div(uint256 a, uint256 b) internal pure returns (uint256) {
        return a / b;
    }

    function test_StrikeFormats() public view {
        // Common call strikes (direct display)
        console.log("=== CALLS (direct) ===");
        console.log("3000e18:", OptionUtils.strike2str(3000e18));
        console.log("2500e18:", OptionUtils.strike2str(2500e18));
        console.log("3500.50e18:", OptionUtils.strike2str(3500.5e18));

        // Put display: simulates name() doing 1e36 / strike()
        console.log("=== PUTS (inverted via 1e36/strike) ===");

        // $2000 put: strike = 0.0005e18 = 500000000000000 (exact)
        uint256 s2000put = 500000000000000;
        console.log("put $2000 display:", OptionUtils.strike2str(1e36 / s2000put));

        // $3000 put: strike ~= 333333333333333 (truncated from 1e18/3000)
        uint256 s3000put = _div(1e18, 3000);
        console.log("put $3000 stored strike:", s3000put);
        console.log("put $3000 display:", OptionUtils.strike2str(1e36 / s3000put));

        // $2500 put: exact
        uint256 s2500put = _div(1e18, 2500);
        console.log("put $2500 display:", OptionUtils.strike2str(1e36 / s2500put));

        // $1500 put: truncated
        uint256 s1500put = _div(1e18, 1500);
        console.log("put $1500 stored strike:", s1500put);
        console.log("put $1500 display:", OptionUtils.strike2str(1e36 / s1500put));

        // $100 put: exact
        uint256 s100put = _div(1e18, 100);
        console.log("put $100 display:", OptionUtils.strike2str(1e36 / s100put));

        // $3 put: truncated
        uint256 s3put = _div(1e18, 3);
        console.log("put $3 stored strike:", s3put);
        console.log("put $3 display:", OptionUtils.strike2str(1e36 / s3put));

        // Fractional
        console.log("=== FRACTIONAL ===");
        console.log("0.5e18:", OptionUtils.strike2str(0.5e18));
        console.log("0.01e18:", OptionUtils.strike2str(0.01e18));
        console.log("1.5e18:", OptionUtils.strike2str(1.5e18));
        console.log("100.123e18:", OptionUtils.strike2str(100.123e18));

        // Edge: raw fractional-only values (no whole part)
        console.log("=== RAW FRACTIONAL (no inversion) ===");
        uint256 raw3000 = _div(1e18, 3000);
        console.log("1/3000:", OptionUtils.strike2str(raw3000));
        uint256 raw1500 = _div(1e18, 1500);
        console.log("1/1500:", OptionUtils.strike2str(raw1500));

        // Meaningful fractional with whole number (should NOT be dropped)
        console.log("=== MEANINGFUL FRACTIONS ===");
        console.log("3000.5e18:", OptionUtils.strike2str(3000.5e18));
        console.log("3000.05e18:", OptionUtils.strike2str(3000.05e18));
        console.log("3000.005e18:", OptionUtils.strike2str(3000.005e18));
        console.log("1.001e18:", OptionUtils.strike2str(1.001e18));
    }
}
