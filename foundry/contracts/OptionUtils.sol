// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/**
 * @title  OptionUtils
 * @author Greek.fi
 * @notice Pure-function library used by {Option} and {Collateral} to render human-readable
 *         token names ("OPT-WETH-USDC-3000-2025-12-26") without blowing up the clone deployment cost.
 * @dev    Contains no state. All functions are `internal pure`. Three concerns:
 *
 *         - `uint2str`      — decimal → ASCII conversion.
 *         - `strike2str`    — 18-decimal fixed point → human string, with sensible rounding and
 *                             scientific notation for very small values (e.g. inverted put strikes).
 *         - `epoch2str`     — unix timestamp → `YYYY-MM-DD` (UTC).
 *
 *         The helpers live here (not inline in Option / Collateral) so every option-pair clone
 *         shares a single deployed copy of the rendering logic.
 */
library OptionUtils {
    /// @notice Convert a uint to its base-10 ASCII representation.
    /// @param _i The number to convert.
    /// @return str The decimal string (e.g. `42 → "42"`; `0 → "0"`).
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

    /// @notice Render an 18-decimal fixed-point strike as a compact, human-readable string.
    /// @dev    Rules applied, in order:
    ///         1. No fractional part → print the integer.
    ///         2. Whole number with ≥4 leading fractional zeros → drop the noise (e.g. floating-point
    ///            artifacts from `1e36 / strike` on puts) and print only the integer.
    ///         3. Whole == 0 and >8 leading zeros → scientific notation (`"1e-9"`).
    ///         4. Otherwise → decimal string, rounded to 4 significant fractional digits and trimmed
    ///            of trailing zeros. Overflow on rounding (e.g. `0.99995 → 1`) is handled.
    /// @param _i Strike price in 18-decimal fixed-point.
    /// @return str Human-readable strike (e.g. `"3000"`, `"0.0005"`, `"1e-9"`).
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

    /// @notice Convert a unix timestamp to a `YYYY-MM-DD` (UTC) string.
    /// @dev    Uses the proleptic Gregorian calendar including leap-year rules (divisible by 4 except
    ///         centuries, which must be divisible by 400). Independent of EVM time zone (block.timestamp
    ///         is always UTC anyway).
    /// @param _i Unix timestamp (seconds since 1970-01-01).
    /// @return str Date string (e.g. `1704067200 → "2024-01-01"`).
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

    /// @notice Gregorian leap-year test.
    /// @param year Four-digit year.
    /// @return `true` if `year` is a leap year.
    function isLeapYear(uint256 year) internal pure returns (bool) {
        if (year % 4 != 0) return false;
        if (year % 100 != 0) return true;
        if (year % 400 != 0) return false;
        return true;
    }
}
