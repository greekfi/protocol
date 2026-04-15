// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

/// @title BlackScholes
/// @notice Stateless Black-Scholes pricing with volatility smile and Greeks.
/// @dev All functions are pure. Internal math uses int256 to minimize type conversions.
///      Volatility smile uses a quadratic skew model:
///      σ(k) = σ_atm · (1 + skew·k + kurtosis·k²), where k = ln(K/S) is log-moneyness.
contract BlackScholes {
    int256 internal constant SQRT_2PI = 2506628274631000502; // √(2π) · 1e18
    int256 internal constant YEAR = 31536000;
    int256 internal constant WAD = 1e18;

    // ============ PRICING ============

    /// @notice Black-Scholes option price with flat volatility
    function price(uint256 spot, uint256 strike, uint256 timeToExpiry, uint256 vol, uint256 rate, bool isPut)
        public
        pure
        returns (uint256)
    {
        // Cast to int256 once at the boundary
        int256 s = int256(spot);
        int256 k = int256(strike);
        int256 v = int256(vol);
        int256 r = int256(rate);
        int256 t = int256(timeToExpiry);

        if (t == 0) return _intrinsic(s, k, isPut);

        if (v == 0) {
            int256 tYears = t * WAD / YEAR;
            int256 pvStrike = _imul(k, _iexpNeg(_imul(r, tYears)));
            if (!isPut) return _pos(s - pvStrike);
            else return _pos(pvStrike - s);
        }

        (int256 d1, int256 d2, int256 expRt) = _computeD1d2(s, k, t, v, r);
        int256 spot_ = s == 0 ? int256(1) : s;

        int256 bsPrice;
        if (!isPut) {
            bsPrice = _imul(spot_, _inormCdf(d1)) - _imul(_imul(k, expRt), _inormCdf(d2));
        } else {
            bsPrice = _imul(_imul(k, expRt), _inormCdf(-d2)) - _imul(spot_, _inormCdf(-d1));
        }

        uint256 intrinsic = _intrinsic(s, k, isPut);
        uint256 result = _pos(bsPrice);
        return result > intrinsic ? result : intrinsic;
    }

    /// @notice Black-Scholes price with volatility smile adjustment
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
    function smileVol(uint256 spot, uint256 strike, uint256 atmVol, int256 skew, int256 kurtosis)
        public
        pure
        returns (uint256)
    {
        if ((skew == 0 && kurtosis == 0) || spot == 0 || strike == 0) return atmVol;

        int256 k = ln(_udiv(strike, spot));
        int256 skewTerm = skew * k / WAD;
        int256 kurtosisTerm = kurtosis * k / WAD * k / WAD;
        int256 multiplier = WAD + skewTerm + kurtosisTerm;

        // Clamp: vol can't go below 10% of ATM or above 500% of ATM
        if (multiplier < 0.1e18) multiplier = 0.1e18;
        if (multiplier > 5e18) multiplier = 5e18;

        int256 vol = int256(atmVol) * multiplier / WAD;

        // Absolute floor/cap
        if (vol < 0.005e18) vol = 0.005e18;
        if (vol > 5e18) vol = 5e18;
        return uint256(vol);
    }

    // ============ GREEKS ============

    /// @notice Delta (∂price/∂spot). Calls: [0, 1e18]. Puts: [-1e18, 0].
    function delta(uint256 spot, uint256 strike, uint256 timeToExpiry, uint256 vol, uint256 rate, bool isPut)
        external
        pure
        returns (int256)
    {
        if (timeToExpiry == 0 || vol == 0) {
            if (!isPut) return spot > strike ? WAD : int256(0);
            else return spot < strike ? -WAD : int256(0);
        }
        (int256 d1,,) = _computeD1d2(int256(spot), int256(strike), int256(timeToExpiry), int256(vol), int256(rate));
        return !isPut ? _inormCdf(d1) : _inormCdf(d1) - WAD;
    }

    /// @notice Gamma (∂²price/∂spot²). Always positive.
    function gamma(uint256 spot, uint256 strike, uint256 timeToExpiry, uint256 vol, uint256 rate)
        external
        pure
        returns (uint256)
    {
        if (timeToExpiry == 0 || spot == 0 || vol == 0) return 0;
        int256 s = int256(spot);
        int256 v = int256(vol);
        (int256 d1,,) = _computeD1d2(s, int256(strike), int256(timeToExpiry), v, int256(rate));
        int256 t = int256(timeToExpiry) * WAD / YEAR;
        int256 sqrtT = int256(Math.sqrt(uint256(t))) * 1e9;
        return _pos(_idiv(_inormalPdf(d1), _imul(s, _imul(v, sqrtT))));
    }

    /// @notice Vega (∂price/∂σ). Always positive.
    function vega(uint256 spot, uint256 strike, uint256 timeToExpiry, uint256 vol, uint256 rate)
        external
        pure
        returns (uint256)
    {
        if (timeToExpiry == 0) return 0;
        int256 s = int256(spot);
        (int256 d1,,) = _computeD1d2(s, int256(strike), int256(timeToExpiry), int256(vol), int256(rate));
        int256 t = int256(timeToExpiry) * WAD / YEAR;
        int256 sqrtT = int256(Math.sqrt(uint256(t))) * 1e9;
        return _pos(_imul(s, _imul(_inormalPdf(d1), sqrtT)));
    }

    /// @notice Theta (∂price/∂time). Annualized. Typically negative for long positions.
    function theta(uint256 spot, uint256 strike, uint256 timeToExpiry, uint256 vol, uint256 rate, bool isPut)
        external
        pure
        returns (int256)
    {
        if (timeToExpiry == 0 || vol == 0) return 0;
        int256 s = int256(spot);
        int256 k = int256(strike);
        int256 v = int256(vol);
        int256 r = int256(rate);
        (int256 d1, int256 d2, int256 expRt) = _computeD1d2(s, k, int256(timeToExpiry), v, r);
        int256 t = int256(timeToExpiry) * WAD / YEAR;
        int256 sqrtT = int256(Math.sqrt(uint256(t))) * 1e9;
        int256 pdf = _inormalPdf(d1);

        int256 term1 = -_idiv(_imul(s, _imul(pdf, v)), 2 * sqrtT);

        if (!isPut) {
            return term1 - _imul(r, _imul(_imul(k, expRt), _inormCdf(d2)));
        } else {
            return term1 + _imul(r, _imul(_imul(k, expRt), _inormCdf(-d2)));
        }
    }

    // ============ INTERNAL: D1/D2 ============

    function _computeD1d2(int256 s, int256 k, int256 timeToExpiry, int256 v, int256 r)
        internal
        pure
        returns (int256 d1, int256 d2, int256 expRt)
    {
        int256 t = timeToExpiry * WAD / YEAR;
        int256 sqrtT = int256(Math.sqrt(uint256(t))) * 1e9;
        int256 sigmaSqrtT = _imul(v, sqrtT);

        int256 underlying = s == 0 ? int256(1) : s;
        int256 lnks = ln(_udiv(uint256(underlying), uint256(k)));

        int256 halfSigma2 = _imul(v, v) / 2;
        int256 mu = _imul(r + halfSigma2, t);

        d1 = _idiv(lnks + mu, sigmaSqrtT);
        d2 = d1 - sigmaSqrtT;
        expRt = _iexpNeg(_imul(r, t));
    }

    /// @notice Standard normal PDF: φ(x) = exp(-x²/2) / √(2π)
    function normalPdf(int256 x) public pure returns (uint256) {
        return _pos(_inormalPdf(x));
    }

    function _inormalPdf(int256 x) internal pure returns (int256) {
        int256 absX = x >= 0 ? x : -x;
        int256 halfXSq = _imul(absX, absX) / 2;
        return _idiv(_iexpNeg(halfXSq), SQRT_2PI);
    }

    function _intrinsic(int256 spot, int256 strike, bool isPut) internal pure returns (uint256) {
        if (!isPut) return _pos(spot - strike);
        else return _pos(strike - spot);
    }

    /// @dev Returns max(0, x) as uint256
    function _pos(int256 x) internal pure returns (uint256) {
        return x > 0 ? uint256(x) : 0;
    }

    // ============ INT256 MATH HELPERS ============

    function _imul(int256 a, int256 b) internal pure returns (int256) {
        return (a * b) / WAD;
    }

    function _idiv(int256 a, int256 b) internal pure returns (int256) {
        return (a * WAD) / b;
    }

    /// @dev int256 wrapper for expNeg (input/output are always non-negative but typed int256 for convenience)
    function _iexpNeg(int256 x) internal pure returns (int256) {
        return int256(expNeg(uint256(x)));
    }

    /// @dev int256 wrapper for normCdf
    function _inormCdf(int256 x) internal pure returns (int256) {
        return int256(normCdf(x));
    }

    // ============ UINT256 MATH (for lookup tables) ============

    function _udiv(uint256 a, uint256 b) internal pure returns (uint256) {
        return (a * 1e18) / b;
    }

    // ============ TRANSCENDENTAL FUNCTIONS ============

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
            uint256 log2Wad = 59794705707972522261;
            uint256 ln2 = 693147180559945309;
            if (log2x >= log2Wad) {
                y = int256((log2x - log2Wad) * ln2 / 1e18);
            } else {
                y = -int256((log2Wad - log2x) * ln2 / 1e18);
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

        uint256[100] memory expGrid = [
            uint256(951229424500713984),
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

        uint256 stepSize = 5e16;
        if (x < stepSize) return 1e18 - x;

        uint256 index = x / stepSize;
        if (index > 99) index = 99;

        uint256 y0 = expGrid[index - 1];
        if (index >= 99) return y0;

        uint256 y1 = expGrid[index];
        uint256 remainder = x - (index * stepSize);
        return y0 - ((y0 - y1) * remainder) / stepSize;
    }

    function normCdf(int256 x) public pure returns (uint256) {
        if (x >= 0) {
            return _normCdfPositive(uint256(x));
        } else {
            return uint256(1e18 - int256(_normCdfPositive(uint256(-x))));
        }
    }

    function _normCdfPositive(uint256 x) internal pure returns (uint256) {
        uint256[101] memory table = [
            uint256(500000000000000000),
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

        uint256 stepSize = 0.05e18;
        uint256 index = x / stepSize;

        if (index >= 100) return 1e18;

        uint256 y0 = table[index];
        uint256 y1 = table[index + 1];
        uint256 remainder = x - (index * stepSize);

        return y0 + ((y1 - y0) * remainder) / stepSize;
    }
}
