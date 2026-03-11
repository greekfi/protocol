// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

/// @title BlackScholes
/// @notice Stateless Black-Scholes pricing with volatility smile and Greeks.
/// @dev All functions are pure. Volatility smile uses a quadratic skew model:
///      σ(k) = σ_atm · (1 + skew·k + kurtosis·k²), where k = ln(K/S) is log-moneyness.
///      Greeks: delta, gamma, vega, theta are computed analytically.
contract BlackScholes {
    uint256 internal constant SQRT_2PI = 2506628274631000502; // √(2π) · 1e18
    uint256 internal constant YEAR = 31536000;

    // ============ PRICING ============

    /// @notice Black-Scholes option price with flat volatility
    /// @param spot Underlying price (18 decimals)
    /// @param strike Strike price (18 decimals)
    /// @param timeToExpiry Time to expiration in seconds
    /// @param vol Annualized volatility (1e18 = 100%, e.g. 0.2e18 = 20%)
    /// @param rate Risk-free rate (1e18 scale, e.g. 0.05e18 = 5%)
    /// @param isPut True for put, false for call
    function price(uint256 spot, uint256 strike, uint256 timeToExpiry, uint256 vol, uint256 rate, bool isPut)
        public
        pure
        returns (uint256)
    {
        if (timeToExpiry == 0) {
            return _intrinsic(spot, strike, isPut);
        }

        if (vol == 0) {
            // Zero vol → discounted intrinsic
            uint256 t = (timeToExpiry * 1e18) / YEAR;
            uint256 pvStrike = _mul18(strike, expNeg(_mul18(rate, t)));
            if (!isPut) return spot > pvStrike ? spot - pvStrike : 0;
            else return pvStrike > spot ? pvStrike - spot : 0;
        }

        (int256 d1, int256 d2, uint256 expRt) = _computeD1D2(spot, strike, timeToExpiry, vol, rate);
        uint256 s = spot == 0 ? 1 : spot;

        uint256 bsPrice;
        if (!isPut) {
            bsPrice = _sub0(_mul18(s, normCdf(d1)), _mul18(_mul18(strike, expRt), normCdf(d2)));
        } else {
            bsPrice = _sub0(_mul18(_mul18(strike, expRt), normCdf(-d2)), _mul18(s, normCdf(-d1)));
        }

        // Floor at intrinsic value (prevents numerical underflow artifacts)
        uint256 intrinsic = _intrinsic(spot, strike, isPut);
        return bsPrice > intrinsic ? bsPrice : intrinsic;
    }

    /// @notice Black-Scholes price with volatility smile adjustment
    /// @param atmVol At-the-money implied volatility (18 decimals)
    /// @param skew Skew coefficient (signed 18 dec). Negative = OTM puts cost more (typical).
    /// @param kurtosis Smile coefficient (signed 18 dec). Positive = wings cost more (typical).
    function priceWithSmile(
        uint256 spot,
        uint256 strike,
        uint256 timeToExpiry,
        uint256 atmVol,
        uint256 rate,
        bool isPut,
        int256 skew,
        int256 kurtosis
    ) external pure returns (uint256) {
        uint256 vol = smileVol(spot, strike, atmVol, skew, kurtosis);
        return price(spot, strike, timeToExpiry, vol, rate, isPut);
    }

    // ============ VOLATILITY SMILE ============

    /// @notice Quadratic skew model: σ(k) = σ_atm · clamp(1 + skew·k + kurtosis·k²)
    /// @dev k = ln(K/S) is log-moneyness. Positive k = OTM call, negative k = OTM put.
    ///      Typical crypto params: skew ≈ -0.15 to -0.3, kurtosis ≈ 0.05 to 0.15.
    ///      Example: spot=3000, strike=2500 (OTM put), skew=-0.2, kurtosis=0.1
    ///      → k = ln(2500/3000) ≈ -0.182, multiplier ≈ 1.04, vol boosted ~4%.
    /// @param spot Underlying price (18 decimals)
    /// @param strike Strike price (18 decimals)
    /// @param atmVol At-the-money volatility (18 decimals)
    /// @param skew Skew coefficient (signed 18 decimals)
    /// @param kurtosis Smile/convexity coefficient (signed 18 decimals)
    /// @return Smile-adjusted volatility (18 decimals), clamped to [0.5%, 500%]
    function smileVol(uint256 spot, uint256 strike, uint256 atmVol, int256 skew, int256 kurtosis)
        public
        pure
        returns (uint256)
    {
        if ((skew == 0 && kurtosis == 0) || spot == 0 || strike == 0) return atmVol;

        // k = ln(K/S)
        int256 k = ln(_div18(strike, spot));

        // multiplier = 1 + skew·k + kurtosis·k²
        int256 skewTerm = (skew * k) / 1e18;
        int256 kurtosisTerm = (kurtosis * k / 1e18 * k) / 1e18;
        int256 multiplier = 1e18 + skewTerm + kurtosisTerm;

        // Clamp: vol can't go below 10% of ATM or above 500% of ATM
        if (multiplier < 0.1e18) multiplier = 0.1e18;
        if (multiplier > 5e18) multiplier = 5e18;

        uint256 vol = uint256(int256(atmVol) * multiplier / 1e18);

        // Absolute floor/cap
        if (vol < 0.005e18) vol = 0.005e18; // 0.5% min
        if (vol > 5e18) vol = 5e18; // 500% max
        return vol;
    }

    // ============ GREEKS ============

    /// @notice Delta (∂price/∂spot)
    /// @return Calls: [0, 1e18]. Puts: [-1e18, 0]. 18 decimal scale.
    function delta(uint256 spot, uint256 strike, uint256 timeToExpiry, uint256 vol, uint256 rate, bool isPut)
        external
        pure
        returns (int256)
    {
        if (timeToExpiry == 0 || vol == 0) {
            if (!isPut) return spot > strike ? int256(1e18) : int256(0);
            else return spot < strike ? -int256(1e18) : int256(0);
        }
        (int256 d1,,) = _computeD1D2(spot, strike, timeToExpiry, vol, rate);
        return !isPut ? int256(normCdf(d1)) : int256(normCdf(d1)) - 1e18;
    }

    /// @notice Gamma (∂²price/∂spot²). Always positive. Same for calls and puts.
    /// @return 18 decimal scale.
    function gamma(uint256 spot, uint256 strike, uint256 timeToExpiry, uint256 vol, uint256 rate)
        external
        pure
        returns (uint256)
    {
        if (timeToExpiry == 0 || spot == 0 || vol == 0) return 0;
        (int256 d1,,) = _computeD1D2(spot, strike, timeToExpiry, vol, rate);
        uint256 t = (timeToExpiry * 1e18) / YEAR;
        uint256 sqrtT = Math.sqrt(t) * 1e9;
        // γ = φ(d1) / (S · σ · √T)
        return _div18(normalPdf(d1), _mul18(spot, _mul18(vol, sqrtT)));
    }

    /// @notice Vega (∂price/∂σ). Always positive. Same for calls and puts.
    /// @return Price change per 1.0 (100pp) vol change, 18 decimal scale.
    ///         For per-1% sensitivity, divide by 100.
    function vega(uint256 spot, uint256 strike, uint256 timeToExpiry, uint256 vol, uint256 rate)
        external
        pure
        returns (uint256)
    {
        if (timeToExpiry == 0) return 0;
        (int256 d1,,) = _computeD1D2(spot, strike, timeToExpiry, vol, rate);
        uint256 t = (timeToExpiry * 1e18) / YEAR;
        uint256 sqrtT = Math.sqrt(t) * 1e9;
        // ν = S · φ(d1) · √T
        return _mul18(spot, _mul18(normalPdf(d1), sqrtT));
    }

    /// @notice Theta (∂price/∂time). Annualized. Typically negative for long positions.
    /// @return Annualized theta, 18 decimal scale (signed). Divide by 365 for daily.
    function theta(uint256 spot, uint256 strike, uint256 timeToExpiry, uint256 vol, uint256 rate, bool isPut)
        external
        pure
        returns (int256)
    {
        if (timeToExpiry == 0 || vol == 0) return 0;
        (int256 d1, int256 d2, uint256 expRt) = _computeD1D2(spot, strike, timeToExpiry, vol, rate);
        uint256 t = (timeToExpiry * 1e18) / YEAR;
        uint256 sqrtT = Math.sqrt(t) * 1e9;
        uint256 pdf = normalPdf(d1);

        // term1 = -S · φ(d1) · σ / (2·√T)
        int256 term1 = -int256(_div18(_mul18(spot, _mul18(pdf, vol)), 2 * sqrtT));

        if (!isPut) {
            // θ_call = term1 - r·K·e^(-rT)·N(d2)
            return term1 - int256(_mul18(rate, _mul18(_mul18(strike, expRt), normCdf(d2))));
        } else {
            // θ_put = term1 + r·K·e^(-rT)·N(-d2)
            return term1 + int256(_mul18(rate, _mul18(_mul18(strike, expRt), normCdf(-d2))));
        }
    }

    // ============ INTERNAL: D1/D2 ============

    function _computeD1D2(uint256 spot, uint256 strike, uint256 timeToExpiry, uint256 vol, uint256 rate)
        internal
        pure
        returns (int256 d1, int256 d2, uint256 expRt)
    {
        uint256 t = (timeToExpiry * 1e18) / YEAR;
        uint256 sqrtT = Math.sqrt(t) * 1e9;
        int256 sigmaSqrtT = int256(_mul18(vol, sqrtT));

        uint256 underlying = spot == 0 ? 1 : spot;
        int256 lnks = ln(_div18(underlying, strike));

        uint256 halfSigma2 = _mul18(vol, vol) / 2;
        int256 mu = int256(_mul18(rate + halfSigma2, t));

        d1 = _div18s(lnks + mu, sigmaSqrtT);
        d2 = d1 - sigmaSqrtT;
        expRt = expNeg(_mul18(rate, t));
    }

    /// @notice Standard normal PDF: φ(x) = exp(-x²/2) / √(2π)
    function normalPdf(int256 x) public pure returns (uint256) {
        uint256 absX = x >= 0 ? uint256(x) : uint256(-x);
        uint256 halfXSq = _mul18(absX, absX) / 2;
        return _div18(expNeg(halfXSq), SQRT_2PI);
    }

    function _intrinsic(uint256 spot, uint256 strike, bool isPut) internal pure returns (uint256) {
        if (!isPut) return spot > strike ? spot - strike : 0;
        else return strike > spot ? strike - spot : 0;
    }

    /// @dev Saturating subtraction (returns 0 instead of reverting on underflow)
    function _sub0(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? a - b : 0;
    }

    // ============ MATH HELPERS ============

    function _mul18(uint256 a, uint256 b) internal pure returns (uint256) {
        return (a * b) / 1e18;
    }

    function _div18(uint256 a, uint256 b) internal pure returns (uint256) {
        return (a * 1e18) / b;
    }

    function _div18s(int256 a, int256 b) internal pure returns (int256) {
        return (a * 1e18) / b;
    }

    function ln(uint256 x) public pure returns (int256 y) {
        require(x > 0, "ln undefined for 0");
        if (x < 1e18) {
            return -_ln(1e36 / x);
        }
        return _ln(x);
    }

    function _ln(uint256 x) internal pure returns (int256 y) {
        unchecked {
            uint256 log2x = log2(x);
            uint256 LOG2_1E18 = 59794705707972522261;
            uint256 LN_2 = 693147180559945309;
            if (log2x >= LOG2_1E18) {
                y = int256((log2x - LOG2_1E18) * LN_2 / 1e18);
            } else {
                y = -int256((LOG2_1E18 - log2x) * LN_2 / 1e18);
            }
        }
    }

    function log2(uint256 x) public pure returns (uint256) {
        require(x > 0, "log2 undefined for 0");

        uint256 msb;
        assembly ("memory-safe") {
            msb := sub(255, clz(x))
        }

        uint256 resultQ64;
        unchecked {
            resultQ64 = msb << 64;
        }

        uint256 r;
        unchecked {
            r = x << (127 - msb);
        }

        unchecked {
            for (uint256 i; i < 64; ++i) {
                r = (r * r) >> 127;
                if (r >= (1 << 128)) {
                    r >>= 1;
                    resultQ64 |= uint256(1) << (63 - i);
                }
            }
        }

        unchecked {
            return (resultQ64 * 1e18) >> 64;
        }
    }

    function expNeg(uint256 x) public pure returns (uint256) {
        if (x > 10 * 1e18) return 0;
        if (x == 0) return 1e18;

        uint64[100] memory expGrid = [
            951229424500713984, 904837418035959552, 860707976425057792, 818730753077981824,
            778800783071404928, 740818220681717888, 704688089718713472, 670320046035639296,
            637628151621773312, 606530659712633472, 576949810380486656, 548811636094026368,
            522045776761015936, 496585303791409472, 472366552741014656, 449328964117221568,
            427414931948726656, 406569659740599040, 386741023454501184, 367879441171442304,
            349937749111155328, 332871083698079552, 316636769379053184, 301194211912202048,
            286504796860190048, 272531793034012608, 259240260645891520, 246596963941606432,
            234570288093797632, 223130160148429792, 212247973826743040, 201896517994655392,
            192049908620754080, 182683524052734624, 173773943450445088, 165298888221586528,
            157237166313627616, 149568619222635040, 142274071586513536, 135335283236612704,
            128734903587804240, 122456428252981904, 116484157773496960, 110803158362333904,
            105399224561864336, 100258843722803744, 95369162215549616, 90717953289412512,
            86293586499370496, 82084998623898800, 78081666001153168, 74273578214333872,
            70651213060429600, 67205512739749760, 63927861206707568, 60810062625217976,
            57844320874838456, 55023220056407232, 52339705948432384, 49787068367863944,
            47358924391140928, 45049202393557800, 42852126867040184, 40762203978366208,
            38774207831722008, 36883167401240016, 35084354100845024, 33373269960326080,
            31745636378067940, 30197383422318500, 28724639654239432, 27323722447292560,
            25991128778755348, 24723526470339388, 23517745856009108, 22370771856165600,
            21279736438377168, 20241911445804392, 19254701775386920, 18315638888734180,
            17422374639493514, 16572675401761254, 15764416484854486, 14995576820477704,
            14264233908999256, 13568559012200934, 12906812580479872, 12277339903068436,
            11678566970395442, 11108996538242306, 10567204383852654, 10051835744633586,
            9561601930543504, 9095277101695816, 8651695203120634, 8229747049020030,
            7828377549225767, 7446583070924338, 7083408929052118, 6737946999085467
        ];

        uint256 stepSize = 5e16;
        if (x < stepSize) return 1e18 - x;

        uint256 index = x / stepSize;
        if (index > 99) index = 99;

        uint256 y0 = uint256(expGrid[index - 1]);
        if (index >= 99) return y0;

        uint256 y1 = uint256(expGrid[index]);
        uint256 remainder = x - (index * stepSize);
        return y0 - ((y0 - y1) * remainder) / stepSize;
    }

    function normCdf(int256 x) public pure returns (uint256) {
        if (x >= 0) {
            return _normCdfPositive(x);
        } else {
            return uint256(1e18 - int256(_normCdfPositive(-x)));
        }
    }

    function _normCdfPositive(int256 x) internal pure returns (uint256) {
        uint64[101] memory table = [
            500000000000000000, 519938805838372480, 539827837277028992, 559617692370242496,
            579259709439102976, 598706325682923648, 617911422188952704, 636830651175619072,
            655421741610324224, 673644779712080000, 691462461274013056, 708840313211653632,
            725746882249926400, 742153889194135296, 758036347776926976, 773372647623131776,
            788144601416603392, 802337456877307648, 815939874653240448, 828943873691518208,
            841344746068542976, 853140943624104064, 864333939053617280, 874928064362849792,
            884930329778291840, 894350226333144704, 903199515414389760, 911492008562598016,
            919243340766228992, 926470740390351744, 933192798731141888, 939429241997940992,
            945200708300441984, 950528531966351872, 955434537241457024, 959940843136182912,
            964069680887074176, 967843225204386304, 971283440183998208, 974411940478361472,
            977249868051820800, 979817784594295552, 982135579437183488, 984222392608909568,
            986096552486501376, 987775527344955392, 989275889978324224, 990613294465161472,
            991802464075403904, 992857189264728576, 993790334674223872, 994613854045933312,
            995338811976281216, 995975411457241728, 996533026196959360, 997020236764945408,
            997444869669571968, 997814038545086720, 998134186699616000, 998411130352635136,
            998650101968369920, 998855793168977280, 999032396786781696, 999183647687171456,
            999312862062084096, 999422974957609216, 999516575857616256, 999595942198135936,
            999663070734323200, 999719706723183744, 999767370920964480, 999807384424364288,
            999840891409842432, 999868879845579520, 999892200266522624, 999911582714799232,
            999927651956074880, 999940941087581056, 999951903655982464, 999960924403402240,
            999968328758166912, 999974391183525888, 999979342493087488, 999983376236270336,
            999986654250984064, 999989311474225152, 999991460094529024, 999993193123400576,
            999994587456092288, 999995706485529984, 999996602326875264, 999997317704220416,
            999997887545297536, 999998340324855680, 999998699192546176, 999998982916757504,
            999999206671848064, 999999382692627968, 999999520816723328, 999999628932592128,
            999999713348428032
        ];

        uint256 stepSize = 0.05e18;
        uint256 scaledX = uint256(x);
        uint256 index = scaledX / stepSize;

        if (index >= 100) return 1e18;

        uint256 y0 = uint256(table[index]);
        uint256 y1 = uint256(table[index + 1]);
        uint256 remainder = scaledX - (index * stepSize);

        return y0 + ((y1 - y0) * remainder) / stepSize;
    }
}
