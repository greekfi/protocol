// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/**
 * @title OptionUtils
 * @notice Shared utility library for Option and Redemption contracts
 * @dev Pure functions for string formatting (strike prices, dates) and math helpers.
 *      Used by both Option.sol and Redemption.sol to avoid code duplication
 *      and reduce clone template deployment costs.
 */
library OptionUtils {
    /**
     * @notice Converts a uint256 to its decimal string representation
     * @param _i The number to convert
     * @return str The string representation
     */
    function uint2str(uint256 _i) internal pure returns (string memory str) {
        if (_i == 0) {
            return "0";
        }
        uint256 j = _i;
        uint256 length;
        while (j != 0) {
            length++;
            j /= 10;
        }
        bytes memory bstr = new bytes(length);
        uint256 k = length;
        j = _i;
        while (j != 0) {
            // casting to uint8 is safe because (j % 10) is always 0-9, adding 48 gives 48-57 (ASCII digits)
            // solhint-disable-next-line no-inline-assembly
            bstr[--k] = bytes1(uint8(48 + j % 10));
            j /= 10;
        }
        str = string(bstr);
    }

    /**
     * @notice Converts an 18-decimal strike price to a human-readable string
     * @dev Handles whole numbers, decimals (up to 4 significant digits),
     *      and scientific notation for very small values.
     * @param _i Strike price in 18-decimal fixed-point
     * @return str Human-readable string (e.g. "3000", "0.0005", "1e-9")
     */
    function strike2str(uint256 _i) internal pure returns (string memory str) {
        uint256 whole = _i / 1e18;
        uint256 fractional = _i % 1e18;

        // If no fractional part, return just the whole number
        if (fractional == 0) {
            return uint2str(whole);
        }

        // Count leading zeros in fractional part
        uint256 leadingZeros = 0;
        uint256 temp = fractional;
        uint256 divisor = 1e17; // Start from first decimal place

        while (leadingZeros < 18 && (temp / divisor) == 0) {
            leadingZeros++;
            divisor /= 10;
        }

        // Drop negligible fractional parts (e.g., 3000.000000000003 from 1e36/x artifacts)
        if (whole > 0 && leadingZeros >= 4) {
            return uint2str(whole);
        }

        // Use scientific notation if >8 leading zeros (very small numbers like 0.000000001)
        if (whole == 0 && leadingZeros > 8) {
            // Find first non-zero digit
            uint256 significand = fractional;
            uint256 exp = leadingZeros + 1;

            // Remove leading zeros
            while (significand > 0 && significand < 1e17) {
                significand *= 10;
            }
            significand /= 1e17; // Get first digit

            return string(abi.encodePacked(uint2str(significand), "e-", uint2str(exp)));
        }

        // Round fractional part to 4 significant digits for clean token names
        uint256 roundedFractional = fractional;
        if (leadingZeros < 14) {
            uint256 keepDigits = leadingZeros + 4;
            if (keepDigits < 18) {
                uint256 divisorForRound = 1;
                for (uint256 i = 0; i < (18 - keepDigits); i++) {
                    divisorForRound *= 10;
                }
                // Round to nearest: (fractional + divisorForRound/2) / divisorForRound * divisorForRound
                // Rewritten to avoid divide-before-multiply: round down to nearest multiple
                uint256 rounded = fractional / divisorForRound;
                uint256 remainder = fractional % divisorForRound;
                // Add 1 if remainder >= divisorForRound/2 (rounding up)
                if (remainder >= divisorForRound / 2) {
                    rounded += 1;
                }
                roundedFractional = rounded * divisorForRound;

                // Check if rounding caused overflow into whole number
                if (roundedFractional >= 1e18) {
                    return uint2str(whole + 1);
                }

                // Check if rounding made it zero
                if (roundedFractional == 0) {
                    return uint2str(whole);
                }
            }
        }

        // Convert fractional part to 18-digit string (with leading zeros)
        bytes memory fracBytes = new bytes(18);
        temp = roundedFractional;
        for (uint256 i = 18; i > 0; i--) {
            // casting to uint8 is safe because (temp % 10) is always 0-9, adding 48 gives 48-57 (ASCII digits)
            // forge-lint: disable-next-line(unsafe-typecast)
            fracBytes[i - 1] = bytes1(uint8(48 + temp % 10));
            temp /= 10;
        }

        // Remove trailing zeros from fractional part
        uint256 len = 18;
        while (len > 0 && fracBytes[len - 1] == "0") {
            len--;
        }

        // If all fractional digits were zeros (shouldn't happen due to check above)
        if (len == 0) {
            return uint2str(whole);
        }

        // Copy non-zero fractional digits to result
        bytes memory fracResult = new bytes(len);
        for (uint256 i = 0; i < len; i++) {
            fracResult[i] = fracBytes[i];
        }

        // Concatenate whole part + decimal point + fractional part
        return string(abi.encodePacked(uint2str(whole), ".", string(fracResult)));
    }

    /**
     * @notice Converts a unix timestamp to ISO date string YYYY-MM-DD
     * @param _i Unix timestamp
     * @return str Date string
     */
    function epoch2str(uint256 _i) internal pure returns (string memory str) {
        // Convert timestamp to days since epoch
        uint256 daysSinceEpoch = _i / 86400; // 86400 seconds per day

        // Calculate year
        uint256 year = 1970;
        uint256 daysInYear;

        while (true) {
            daysInYear = isLeapYear(year) ? 366 : 365;
            if (daysSinceEpoch >= daysInYear) {
                daysSinceEpoch -= daysInYear;
                year++;
            } else {
                break;
            }
        }

        // Calculate month and day
        uint256 month = 1;
        uint256[12] memory daysInMonth = [uint256(31), 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];

        // Adjust February for leap year
        if (isLeapYear(year)) {
            daysInMonth[1] = 29;
        }

        for (uint256 i = 0; i < 12; i++) {
            if (daysSinceEpoch >= daysInMonth[i]) {
                daysSinceEpoch -= daysInMonth[i];
                month++;
            } else {
                break;
            }
        }

        uint256 day = daysSinceEpoch + 1; // Days are 1-indexed

        // Format as YYYY-MM-DD
        return string(
            abi.encodePacked(
                uint2str(year),
                "-",
                month < 10 ? string(abi.encodePacked("0", uint2str(month))) : uint2str(month),
                "-",
                day < 10 ? string(abi.encodePacked("0", uint2str(day))) : uint2str(day)
            )
        );
    }

    function isLeapYear(uint256 year) internal pure returns (bool) {
        if (year % 4 != 0) return false;
        if (year % 100 != 0) return true;
        if (year % 400 != 0) return false;
        return true;
    }
}
