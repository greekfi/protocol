// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

import { console } from "forge-std/console.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

interface IUniswapV3Pool {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function slot0()
        external
        view
        returns (
            uint160 sqrtPriceX96,
            int24 tick,
            uint16 observationIndex,
            uint16 observationCardinality,
            uint16 observationCardinalityNext,
            uint8 feeProtocol,
            bool unlocked
        );
}

contract OptionPrice {
    // Black-Scholes option pricing formula (returns price with 18 decimals)
    // underlying: price of the underlying asset (18 decimals)
    // strike: strike price (18 decimals)
    // timeToExpiration: time to expiration in seconds
    // volatility: annualized volatility (scaled by 1e18, e.g. 0.2 * 1e18 for 20%)
    // riskFreeRate: annualized risk-free rate (scaled by 1e18, e.g. 0.05 * 1e18 for 5%)
    // isCall: true for call, false for put
    function blackScholesPrice(
        uint256 underlying,
        uint256 strike,
        uint256 timeToExpiration,
        uint256 volatility,
        uint256 r,
        bool isPut
    ) public pure returns (uint256 price) {
        // All values are in 1e18 fixed point
        // timeToExpiration is in seconds, convert to years (divide by 31536000)
        if (timeToExpiration == 0) {
            // Option has expired
            if (!isPut) {
                return underlying > strike ? underlying - strike : 0;
            } else {
                return strike > underlying ? strike - underlying : 0;
            }
        }
        uint256 t = (timeToExpiration * 1e18) / 31536000; // t in years, 1e18 fixed point
            // console.log("Time to expiration (years):", t);

        // sigma * sqrt(t)
        // OpenZeppelin's sqrt: sqrt(a*1e18) = sqrt(a)*1e9
        uint256 sqrtT = Math.sqrt(t); // Returns sqrt with half decimals (1e9)
        int256 sigmaSqrtT = int256(mul18(volatility, sqrtT * 1e9)); // Restore to 1e18

        if (underlying == 0) underlying = 1;
        uint256 ks = div18(underlying, strike);

        require(ks >= 0, "strike cannot be zero");
        // ln(underlying/strike)
        int256 lnks = ln(ks);

        // (r + 0.5 * sigma^2) * t
        uint256 halfSigma2 = mul18(volatility, volatility) / 2;
        int256 mu = int256(mul18((r + halfSigma2), t));

        // d1 = (ln(U/S) + (r + 0.5*sigma^2)*t) / (sigma*sqrt(t))
        int256 d1 = div18(lnks + mu, sigmaSqrtT);

        // d2 = d1 - sigma*sqrt(t)
        int256 d2 = d1 - sigmaSqrtT;

        // N(d1), N(d2)
        uint256 nd1 = normCdf(d1);
        uint256 nd2 = normCdf(d2);
        uint256 nd1n = normCdf(-d1);
        uint256 nd2n = normCdf(-d2);
        // console.log("d1, d2:", abs(d1), abs(d2));
        // console.log("N(d1), N(d2):", nd1, nd2);
        // console.log("N(-d1), N(-d2):", nd1n, nd2n);

        // exp(-r*t)
        uint256 expRt = expNeg(mul18(r, t));
        // console.log("exp(-r*t):", expRt);
        if (!isPut) {
            // C = U * N(d1) - S * exp(-r*t) * N(d2)
            // uint256 part1 = mul18(underlying, nd1);
            // uint256 part2 = mul18(mul18(strike, expRt), nd2);
            // console.log("Call parts:", part1, part2);
            price = mul18(underlying, nd1) - mul18(mul18(strike, expRt), nd2);
        } else {
            // P = S * exp(-r*t) * N(-d2) - U * N(-d1)
            // uint256 part1 = mul18(mul18(strike, expRt), nd2n);
            // uint256 part2 = mul18(underlying, nd1n);
            // console.log("Put parts:", part1, part2);
            price = mul18(mul18(strike, expRt), nd2n) - mul18(underlying, nd1n);
        }
    }

    function mul18(int256 a, int256 b) public pure returns (int256) {
        return (a * b) / 1e18;
    }

    function mul18(uint256 a, uint256 b) public pure returns (uint256) {
        return (a * b) / 1e18;
    }

    function div18(int256 a, int256 b) public pure returns (int256) {
        return (a * 1e18) / b;
    }

    function div18(uint256 a, uint256 b) public pure returns (uint256) {
        return (a * 1e18) / b;
    }

    // --- Math helpers ---
    // Optimized logarithm functions using CLZ (Count Leading Zeros) opcode

    // Natural logarithm (ln) for 1e18 fixed point, returns 1e18 fixed point
    // Handles both x >= 1e18 and x < 1e18 using ln(1/x) = -ln(x) identity
    function ln(uint256 x) public pure returns (int256 y) {
        require(x > 0, "ln undefined for 0");

        if (x < 1e18) {
            // For x < 1: ln(x) = -ln(1/x)
            // 1/x in 1e18 fixed point = 1e36 / x
            return -ln_(1e36 / x);
        }
        return ln_(x);
    }

    // Internal helper for ln() - converts log2 to natural log
    // Formula: ln(x) = log2(x) * ln(2)
    // ln(2) ≈ 0.693147180559945309417232121458 (in 1e18: 693147180559945309)
    // log2(1e18) ≈ 59.794705707972522261 (in 1e18: 59794705707972522261)
    // This adjusts log2 result from base 1e18 to actual ln value
    function ln_(uint256 x) internal pure returns (int256 y) {
        unchecked {
            // Convert log2(x) to ln(x):
            // ln(x) = (log2(x) - log2(1e18)) * ln(2)
            // This accounts for our 1e18 fixed-point representation
            uint256 log2x = log2(x);

            // Constant: log2(1e18) in 1e18 fixed point
            uint256 LOG2_1E18 = 59794705707972522261;

            // Constant: ln(2) in 1e18 fixed point (0.693147180559945309...)
            uint256 LN_2 = 693147180559945309;

            // Calculate: (log2(x) - log2(1e18)) * ln(2) / 1e18
            if (log2x >= LOG2_1E18) {
                y = int256((log2x - LOG2_1E18) * LN_2 / 1e18);
            } else {
                y = -int256((LOG2_1E18 - log2x) * LN_2 / 1e18);
            }
        }
    }

    // Optimized log2 with fractional precision using CLZ opcode
    // Uses CLZ (Count Leading Zeros) from Fusaka/Pectra (Solidity 0.8.33+)
    // Returns log2(x) in 1e18 fixed point
    //
    // Algorithm:
    // 1. Use CLZ to find MSB (integer part of log2)
    // 2. Normalize x to range [1, 2)
    // 3. Iteratively refine fractional bits using bit-by-bit algorithm (64 bits)
    // 4. Convert from Q64.64 to 1e18 fixed point
    function log2(uint256 x) public pure returns (uint256) {
        require(x > 0, "log2 undefined for 0");

        // 1) Integer part using CLZ opcode
        // CLZ counts leading zeros from MSB, so: msb_position = 255 - clz(x)
        uint256 msb;
        assembly ("memory-safe") {
            msb := sub(255, clz(x))
        }

        // 2) Start result as Q64.64 fixed point with integer part
        // Q64.64 means 64 bits for integer, 64 bits for fraction
        uint256 resultQ64;
        unchecked {
            resultQ64 = msb << 64; // Integer part in upper 64 bits
        }

        // 3) Normalize x to r in [1, 2) as Q128 fixed point
        // Shift x left so MSB is at position 127 (Q128 representation)
        uint256 r;
        unchecked {
            r = x << (127 - msb);
        }

        // 4) Compute 64 fractional bits using bit-by-bit refinement
        // For each bit: square r, if r >= 2, set bit and divide by 2
        unchecked {
            for (uint256 i; i < 64; ++i) {
                r = (r * r) >> 127; // Square and maintain Q128

                if (r >= (1 << 128)) {
                    r >>= 1;
                    resultQ64 |= uint256(1) << (63 - i);
                }
            }
        }

        // 5) Convert from Q64.64 to 1e18 fixed point
        // Q64.64 to decimal: multiply by 1e18 and shift right 64 bits
        unchecked {
            return (resultQ64 * 1e18) >> 64;
        }
    }

    // Exponential function e^{-x}, x >= 0 in 1e18 fixed point, returns 1e18 fixed point
    // This is specialized for exp(-x) where x > 0, as used in Black-Scholes
    function expNeg(uint256 x) public pure returns (uint256) {
        if (x > 10 * 1e18) {
            return 0;
        }
        if (x == 0) {
            return 1e18;
        }
        // Use uint64 to match the literal values and avoid type conversion error
        uint64[100] memory expGrid = [
            951229424500713984,
            904837418035959552,
            860707976425057792,
            818730753077981824,
            778800783071404928,
            740818220681717888,
            704688089718713472,
            670320046035639296,
            637628151621773312,
            606530659712633472,
            576949810380486656,
            548811636094026368,
            522045776761015936,
            496585303791409472,
            472366552741014656,
            449328964117221568,
            427414931948726656,
            406569659740599040,
            386741023454501184,
            367879441171442304,
            349937749111155328,
            332871083698079552,
            316636769379053184,
            301194211912202048,
            286504796860190048,
            272531793034012608,
            259240260645891520,
            246596963941606432,
            234570288093797632,
            223130160148429792,
            212247973826743040,
            201896517994655392,
            192049908620754080,
            182683524052734624,
            173773943450445088,
            165298888221586528,
            157237166313627616,
            149568619222635040,
            142274071586513536,
            135335283236612704,
            128734903587804240,
            122456428252981904,
            116484157773496960,
            110803158362333904,
            105399224561864336,
            100258843722803744,
            95369162215549616,
            90717953289412512,
            86293586499370496,
            82084998623898800,
            78081666001153168,
            74273578214333872,
            70651213060429600,
            67205512739749760,
            63927861206707568,
            60810062625217976,
            57844320874838456,
            55023220056407232,
            52339705948432384,
            49787068367863944,
            47358924391140928,
            45049202393557800,
            42852126867040184,
            40762203978366208,
            38774207831722008,
            36883167401240016,
            35084354100845024,
            33373269960326080,
            31745636378067940,
            30197383422318500,
            28724639654239432,
            27323722447292560,
            25991128778755348,
            24723526470339388,
            23517745856009108,
            22370771856165600,
            21279736438377168,
            20241911445804392,
            19254701775386920,
            18315638888734180,
            17422374639493514,
            16572675401761254,
            15764416484854486,
            14995576820477704,
            14264233908999256,
            13568559012200934,
            12906812580479872,
            12277339903068436,
            11678566970395442,
            11108996538242306,
            10567204383852654,
            10051835744633586,
            9561601930543504,
            9095277101695816,
            8651695203120634,
            8229747049020030,
            7828377549225767,
            7446583070924338,
            7083408929052118,
            6737946999085467
        ];
        // Table covers x in [0.05, 5.00] with step size 0.05
        // expGrid[0] = e^(-0.05), expGrid[1] = e^(-0.10), ..., expGrid[99] = e^(-5.00)
        uint256 stepSize = 5e16; // 0.05e18

        // For very small x (< 0.05), approximate as e^(-x) ≈ 1 - x (first-order Taylor)
        if (x < stepSize) {
            return 1e18 - x; // Linear approximation for small x
        }

        // Calculate index for table lookup with interpolation
        uint256 index = x / stepSize;
        if (index > 99) index = 99;

        // Get base value (note: table starts at index 0 = e^(-0.05))
        uint256 y0 = uint256(expGrid[index - 1]); // index-1 because table[0] = e^(-0.05)

        if (index >= 99) return y0; // At edge of table

        // Get next value for interpolation
        uint256 y1 = uint256(expGrid[index]);

        // Calculate fractional part for linear interpolation
        uint256 remainder = x - (index * stepSize);

        // Linear interpolation: y = y0 + (y1 - y0) * (remainder / stepSize)
        // Note: y1 < y0 for exponential decay, so we subtract
        uint256 interpolated = y0 - ((y0 - y1) * remainder) / stepSize;

        return interpolated;
    }

    function abs(int256 x) public pure returns (uint256) {
        return uint256(x >= 0 ? x : -x);
    }

    // Standard normal CDF using lookup table for common values
    function normCdf(int256 x) public pure returns (uint256) {
        if (x >= 0) {
            return normCdfPositive(x);
        } else {
            return uint256(1e18 - int256(normCdfPositive(-x)));
        }
    }

    function normCdfPositive(int256 x) internal pure returns (uint256) {
        uint64[101] memory table = [
            500000000000000000,
            519938805838372480,
            539827837277028992,
            559617692370242496,
            579259709439102976,
            598706325682923648,
            617911422188952704,
            636830651175619072,
            655421741610324224,
            673644779712080000,
            691462461274013056,
            708840313211653632,
            725746882249926400,
            742153889194135296,
            758036347776926976,
            773372647623131776,
            788144601416603392,
            802337456877307648,
            815939874653240448,
            828943873691518208,
            841344746068542976,
            853140943624104064,
            864333939053617280,
            874928064362849792,
            884930329778291840,
            894350226333144704,
            903199515414389760,
            911492008562598016,
            919243340766228992,
            926470740390351744,
            933192798731141888,
            939429241997940992,
            945200708300441984,
            950528531966351872,
            955434537241457024,
            959940843136182912,
            964069680887074176,
            967843225204386304,
            971283440183998208,
            974411940478361472,
            977249868051820800,
            979817784594295552,
            982135579437183488,
            984222392608909568,
            986096552486501376,
            987775527344955392,
            989275889978324224,
            990613294465161472,
            991802464075403904,
            992857189264728576,
            993790334674223872,
            994613854045933312,
            995338811976281216,
            995975411457241728,
            996533026196959360,
            997020236764945408,
            997444869669571968,
            997814038545086720,
            998134186699616000,
            998411130352635136,
            998650101968369920,
            998855793168977280,
            999032396786781696,
            999183647687171456,
            999312862062084096,
            999422974957609216,
            999516575857616256,
            999595942198135936,
            999663070734323200,
            999719706723183744,
            999767370920964480,
            999807384424364288,
            999840891409842432,
            999868879845579520,
            999892200266522624,
            999911582714799232,
            999927651956074880,
            999940941087581056,
            999951903655982464,
            999960924403402240,
            999968328758166912,
            999974391183525888,
            999979342493087488,
            999983376236270336,
            999986654250984064,
            999989311474225152,
            999991460094529024,
            999993193123400576,
            999994587456092288,
            999995706485529984,
            999996602326875264,
            999997317704220416,
            999997887545297536,
            999998340324855680,
            999998699192546176,
            999998982916757504,
            999999206671848064,
            999999382692627968,
            999999520816723328,
            999999628932592128,
            999999713348428032
        ];

        // Step size is 0.05e18
        uint256 stepSize = 0.05e18;

        // Calculate index and fractional part for interpolation
        uint256 scaledX = uint256(x);
        uint256 index = scaledX / stepSize;

        if (index >= 100) return 1e18;

        // Get the two surrounding table values
        uint256 y0 = uint256(table[index]);
        uint256 y1 = uint256(table[index + 1]);

        // Calculate fractional part (how far between index and index+1)
        uint256 remainder = scaledX - (index * stepSize);

        // Linear interpolation: y = y0 + (y1 - y0) * (remainder / stepSize)
        uint256 interpolated = y0 + ((y1 - y0) * remainder) / stepSize;

        return interpolated;
    }

    // Returns the price of the token (18 decimals)
    function getPrice(uint256 collateralPrice, uint256 strike, uint256 expiration, bool isPut, bool inverse)
        external
        view
        returns (uint256)
    {
        uint256 timeToExpiration = expiration > block.timestamp ? expiration - block.timestamp : 0;

        uint256 price = blackScholesPrice(collateralPrice, strike, timeToExpiration, 0.2 * 1e18, 0.05 * 1e18, isPut);

        if (inverse && price > 0) {
            return 1e36 / price;
        }
        return price;
    }
}
