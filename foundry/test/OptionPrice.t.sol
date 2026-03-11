// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { Test, console } from "forge-std/Test.sol";
import { BlackScholes } from "../contracts/BlackScholes.sol";

contract BlackScholesTest is Test {
    BlackScholes public bs;

    function setUp() public {
        bs = new BlackScholes();
    }

    // ============ EXISTING TESTS ============

    function testExpNegZero() public view {
        assertEq(bs.expNeg(0), 1e18, "expNeg(0) should equal 1");
    }

    function testExpNegOne() public view {
        assertApproxEqRel(bs.expNeg(1e18), 367879441171442321, 0.01e18, "expNeg(1) should be approximately 0.3679");
        assertApproxEqRel(bs.expNeg(2e18), 135335283236612691, 0.01e18, "expNeg(2) should be approximately 0.1353");
        assertEq(bs.expNeg(11e18), 0, "expNeg(11) should equal 0");
        assertEq(bs.expNeg(100e18), 0, "expNeg(100) should equal 0");
    }

    function testCDF() public view {
        assertApproxEqRel(bs.normCdf(0), 0.5e18, 0.01e18, "CDF(0) should equal 0.5");
        assertApproxEqRel(
            bs.normCdf(1e18), uint256(841344746068542948), uint256(5e16), "CDF(1) should be approximately 0.8413"
        );
        assertApproxEqRel(bs.normCdf(-1e18), 158655253931457051, 0.05e18, "CDF(-1) should be approximately 0.1587");
        assertApproxEqRel(bs.normCdf(2e18), 977249868051820792, 0.05e18, "CDF(2) should be approximately 0.9772");
    }

    function testBlackScholesATMCall() public view {
        uint256 callPrice = bs.price(100e18, 100e18, 31536000, 0.2e18, 0.05e18, false);
        assertApproxEqRel(
            callPrice, 10450000000000000000, 0.1e18, "ATM call option price should be approximately $10.45"
        );
    }

    function testBlackScholesATMPut() public view {
        uint256 putPrice = bs.price(100e18, 100e18, 31536000, 0.2e18, 0.05e18, true);
        assertApproxEqRel(putPrice, 5.57e18, 0.1e18, "ATM put option price should be approximately $5.57");
    }

    function testBlackScholesExpiredATMCall() public view {
        uint256 expiredCallPrice = bs.price(100e18, 100e18, 0, 0.2e18, 0.05e18, false);
        assertEq(expiredCallPrice, 0, "Expired ATM call should have 0 value");
    }

    function testBlackScholesExpiredITMCall() public view {
        uint256 itmExpiredCallPrice = bs.price(120e18, 100e18, 100, 0.2e18, 0.05e18, false);
        assertApproxEqRel(itmExpiredCallPrice, 20e18, 0.3e18, "Expired ITM call should have intrinsic value of $20");
    }

    function testBlackScholesDebug() public view {
        uint256 callPrice = bs.price(100e18, 100e18, 31536000, 0.2e18, 0.05e18, false);
        console.log("Final call price:", callPrice);
    }

    function test_ln() public view {
        assertEq(bs.log2(1.0e18), 59.794705707972522261e18, "log2(1) should equal 59.794705");
        assertApproxEqRel(bs.ln(1.0e18), 0, 0.0001e18, "ln(1) should be approximately 0");
        assertApproxEqRel(bs.ln(1.5e18), 0.405465108108164381e18, 0.01e18, "ln(1.5) should be approximately 0.4055");
        assertApproxEqRel(bs.ln(2e18), 693147180559945309, 0.01e18, "ln(2) should be approximately 0.6931");
        assertApproxEqRel(bs.ln(1.05e18), 48790164169432048, 0.01e18, "ln(1.05) should be approximately 0.0488");
        assertEq(bs.ln(1e18), 0, "ln(1) should equal 0");
    }

    function test_normCDF_BlackScholes_values() public view {
        int256 d1 = 350000000000000000;
        int256 d2 = 150000000000000000;
        uint256 nd1 = bs.normCdf(d1);
        uint256 nd2 = bs.normCdf(d2);
        assertApproxEqRel(nd1, 636800000000000000, 0.1e18, "N(0.35) should be approximately 0.6368");
        assertApproxEqRel(nd2, 559600000000000000, 0.1e18, "N(0.15) should be approximately 0.5596");
    }

    function testPrice() public view {
        uint256 timeToExpiry = 1758143415 > block.timestamp ? 1758143415 - block.timestamp : 0;
        uint256 bsPrice = bs.price(4600e18, 3000e18, timeToExpiry, 0.2e18, 0.05e18, false);
        console.log("option price", bsPrice / 1e18);
    }

    function testBlackScholes1() public view {
        uint256 callPrice = bs.price(2980e18, 3100e18, 1 weeks, 0.6e18, 0.04e18, false);
        console.log("Final call price:", callPrice);
        uint256 putPrice = bs.price(2980e18, 3100e18, 1 weeks, 0.6e18, 0.04e18, true);
        console.log("Final put price:", putPrice);
    }

    // ============ NORMAL PDF ============

    function testNormalPdfAtZero() public view {
        // φ(0) = 1/√(2π) ≈ 0.3989
        uint256 pdf = bs.normalPdf(0);
        assertApproxEqRel(pdf, 0.3989e18, 0.01e18, "PDF(0) should be approximately 0.3989");
    }

    function testNormalPdfSymmetry() public view {
        uint256 pdfPos = bs.normalPdf(1e18);
        uint256 pdfNeg = bs.normalPdf(-1e18);
        assertEq(pdfPos, pdfNeg, "PDF should be symmetric");
    }

    function testNormalPdfTails() public view {
        // φ(3) ≈ 0.00443
        uint256 pdf3 = bs.normalPdf(3e18);
        assertApproxEqRel(pdf3, 0.00443e18, 0.1e18, "PDF(3) should be approximately 0.00443");
        // φ(0) > φ(1) > φ(3)
        assertGt(bs.normalPdf(0), bs.normalPdf(1e18));
        assertGt(bs.normalPdf(1e18), bs.normalPdf(3e18));
    }

    // ============ VOLATILITY SMILE ============

    function testSmileVolATM() public view {
        // ATM: k = ln(1) = 0, so smile has no effect regardless of skew/kurtosis
        uint256 vol = bs.smileVol(100e18, 100e18, 0.6e18, -0.2e18, 0.1e18);
        assertEq(vol, 0.6e18, "ATM smile vol should equal ATM vol");
    }

    function testSmileVolOTMPut() public view {
        // OTM put: strike < spot, k = ln(K/S) < 0
        // With negative skew, vol should increase for OTM puts
        uint256 flatVol = 0.6e18;
        uint256 smiledVol = bs.smileVol(3000e18, 2500e18, flatVol, -0.2e18, 0.1e18);
        assertGt(smiledVol, flatVol, "OTM put should have higher vol with negative skew");
        console.log("OTM put smile vol:", smiledVol);
    }

    function testSmileVolOTMCall() public view {
        // OTM call: strike > spot, k = ln(K/S) > 0
        // With negative skew, OTM calls get slightly lower vol
        // Kurtosis adds it back for far OTM
        uint256 flatVol = 0.6e18;
        uint256 smiledVol = bs.smileVol(3000e18, 3500e18, flatVol, -0.2e18, 0.1e18);
        console.log("OTM call smile vol:", smiledVol);
        // With skew=-0.2 and kurtosis=0.1, slight OTM call has lower vol
        // k ≈ ln(3500/3000) ≈ 0.154
        // multiplier = 1 + (-0.2)(0.154) + (0.1)(0.154²) ≈ 1 - 0.031 + 0.002 ≈ 0.971
        assertLt(smiledVol, flatVol, "Slightly OTM call with negative skew should have lower vol");
    }

    function testSmileVolSymmetricKurtosis() public view {
        // Pure kurtosis (no skew) should produce symmetric smile
        uint256 flatVol = 0.5e18;
        uint256 volAbove = bs.smileVol(100e18, 120e18, flatVol, 0, 0.5e18);
        uint256 volBelow = bs.smileVol(100e18, 83.33e18, flatVol, 0, 0.5e18);
        // ln(120/100) ≈ 0.182, ln(83.33/100) ≈ -0.182
        // Both should get same boost from kurtosis
        assertApproxEqRel(volAbove, volBelow, 0.05e18, "Symmetric kurtosis should produce equal wing vols");
        assertGt(volAbove, flatVol, "Wings should have higher vol with positive kurtosis");
    }

    function testSmileVolZeroParams() public view {
        // Zero skew and kurtosis returns flat vol
        uint256 vol = bs.smileVol(100e18, 90e18, 0.3e18, 0, 0);
        assertEq(vol, 0.3e18);
    }

    function testSmileVolClamping() public view {
        // Extreme params should be clamped, not overflow
        uint256 vol = bs.smileVol(100e18, 10e18, 0.3e18, -10e18, 0);
        // k = ln(10/100) = ln(0.1) ≈ -2.3, skewTerm = -10 * -2.3 = 23
        // multiplier = 1 + 23 = 24, clamped to 5
        assertEq(vol, 1.5e18, "Extreme params should be clamped to 5x ATM");
    }

    // ============ PRICE WITH SMILE ============

    function testPriceWithSmileATM() public view {
        // At ATM, smile should give same price as flat vol
        uint256 flatPrice = bs.price(100e18, 100e18, 31536000, 0.2e18, 0.05e18, false);
        uint256 smilePrice = bs.priceWithSmile(100e18, 100e18, 31536000, 0.2e18, 0.05e18, false, -0.2e18, 0.1e18);
        assertEq(smilePrice, flatPrice, "ATM smile price should equal flat price");
    }

    function testPriceWithSmileOTMPut() public view {
        // OTM put with negative skew should be more expensive than flat vol
        uint256 flatPrice = bs.price(3000e18, 2500e18, 30 days, 0.6e18, 0.04e18, true);
        uint256 smilePrice = bs.priceWithSmile(3000e18, 2500e18, 30 days, 0.6e18, 0.04e18, true, -0.2e18, 0.1e18);
        assertGt(smilePrice, flatPrice, "OTM put with neg skew should cost more");
        console.log("OTM put flat:", flatPrice);
        console.log("OTM put smile:", smilePrice);
    }

    // ============ GREEKS: DELTA ============

    function testDeltaATMCall() public view {
        // ATM call 1yr, 20% vol, 5% rate → delta ≈ 0.6368
        int256 d = bs.delta(100e18, 100e18, 31536000, 0.2e18, 0.05e18, false);
        assertApproxEqRel(uint256(d), 0.6368e18, 0.05e18, "ATM call delta should be ~0.6368");
    }

    function testDeltaATMPut() public view {
        // ATM put delta ≈ -0.3632 (= delta_call - 1)
        int256 d = bs.delta(100e18, 100e18, 31536000, 0.2e18, 0.05e18, true);
        assertApproxEqAbs(d, -0.3632e18, 0.05e18, "ATM put delta should be ~-0.3632");
    }

    function testDeltaDeepITMCall() public view {
        // Deep ITM call: delta → 1.0
        int256 d = bs.delta(200e18, 100e18, 31536000, 0.2e18, 0.05e18, false);
        assertGt(d, 0.95e18, "Deep ITM call delta should be close to 1.0");
    }

    function testDeltaDeepOTMCall() public view {
        // Deep OTM call: delta → 0
        int256 d = bs.delta(50e18, 100e18, 31536000, 0.2e18, 0.05e18, false);
        assertLt(d, 0.05e18, "Deep OTM call delta should be close to 0");
    }

    function testDeltaExpired() public view {
        assertEq(bs.delta(120e18, 100e18, 0, 0.2e18, 0.05e18, false), 1e18, "Expired ITM call delta = 1");
        assertEq(bs.delta(80e18, 100e18, 0, 0.2e18, 0.05e18, false), 0, "Expired OTM call delta = 0");
        assertEq(bs.delta(80e18, 100e18, 0, 0.2e18, 0.05e18, true), -1e18, "Expired ITM put delta = -1");
    }

    function testDeltaPutCallParity() public view {
        // delta_call - delta_put = 1 (approximately, adjusted for discounting)
        int256 dCall = bs.delta(100e18, 100e18, 31536000, 0.3e18, 0.05e18, false);
        int256 dPut = bs.delta(100e18, 100e18, 31536000, 0.3e18, 0.05e18, true);
        // delta_call - delta_put should ≈ 1
        assertApproxEqAbs(dCall - dPut, 1e18, 0.001e18, "Delta put-call parity should hold");
    }

    // ============ GREEKS: GAMMA ============

    function testGammaATM() public view {
        // ATM gamma for S=100, K=100, T=1yr, σ=20%, r=5%
        // γ = φ(d1) / (S·σ·√T) ≈ 0.3752 / (100·0.2·1) ≈ 0.01876
        uint256 g = bs.gamma(100e18, 100e18, 31536000, 0.2e18, 0.05e18);
        assertApproxEqRel(g, 0.01876e18, 0.1e18, "ATM gamma should be ~0.01876");
    }

    function testGammaCallEqualsPut() public view {
        // Gamma is the same for calls and puts (only one gamma function, no isPut param)
        // This is by definition since gamma depends only on d1
        uint256 g = bs.gamma(100e18, 110e18, 31536000, 0.2e18, 0.05e18);
        assertGt(g, 0, "Gamma should be positive");
    }

    function testGammaExpired() public view {
        assertEq(bs.gamma(100e18, 100e18, 0, 0.2e18, 0.05e18), 0, "Expired gamma should be 0");
    }

    function testGammaHighestATM() public view {
        // Gamma is highest at ATM
        uint256 gATM = bs.gamma(100e18, 100e18, 31536000, 0.3e18, 0.05e18);
        uint256 gOTM = bs.gamma(100e18, 130e18, 31536000, 0.3e18, 0.05e18);
        uint256 gITM = bs.gamma(100e18, 70e18, 31536000, 0.3e18, 0.05e18);
        assertGt(gATM, gOTM, "ATM gamma should exceed OTM gamma");
        assertGt(gATM, gITM, "ATM gamma should exceed ITM gamma");
    }

    // ============ GREEKS: VEGA ============

    function testVegaATM() public view {
        // ATM vega: S·φ(d1)·√T = 100·0.3752·1 = 37.52
        uint256 v = bs.vega(100e18, 100e18, 31536000, 0.2e18, 0.05e18);
        assertApproxEqRel(v, 37.52e18, 0.1e18, "ATM vega should be ~37.52");
    }

    function testVegaExpired() public view {
        assertEq(bs.vega(100e18, 100e18, 0, 0.2e18, 0.05e18), 0);
    }

    function testVegaHighestATM() public view {
        uint256 vATM = bs.vega(100e18, 100e18, 31536000, 0.3e18, 0.05e18);
        uint256 vOTM = bs.vega(100e18, 140e18, 31536000, 0.3e18, 0.05e18);
        assertGt(vATM, vOTM, "ATM vega should exceed OTM vega");
    }

    // ============ GREEKS: THETA ============

    function testThetaATMCall() public view {
        // θ_call (annualized) ≈ -6.41 for S=K=100, T=1yr, σ=20%, r=5%
        int256 th = bs.theta(100e18, 100e18, 31536000, 0.2e18, 0.05e18, false);
        assertLt(th, 0, "Call theta should be negative (time decay)");
        assertApproxEqAbs(th, -6.41e18, 1e18, "ATM call theta should be approximately -6.41 per year");
    }

    function testThetaATMPut() public view {
        // Put theta is less negative than call theta (rate benefit)
        int256 thCall = bs.theta(100e18, 100e18, 31536000, 0.2e18, 0.05e18, false);
        int256 thPut = bs.theta(100e18, 100e18, 31536000, 0.2e18, 0.05e18, true);
        assertLt(thCall, thPut, "Call theta should be more negative than put theta");
    }

    function testThetaExpired() public view {
        assertEq(bs.theta(100e18, 100e18, 0, 0.2e18, 0.05e18, false), 0);
    }

    // ============ EDGE CASES ============

    function testPriceZeroVol() public view {
        // Zero vol → discounted intrinsic for ITM, 0 for OTM
        uint256 itmCall = bs.price(120e18, 100e18, 31536000, 0, 0.05e18, false);
        // PV of strike = 100 * exp(-0.05) ≈ 95.12
        // intrinsic ≈ 120 - 95.12 = 24.88
        assertApproxEqRel(itmCall, 24.88e18, 0.05e18, "Zero vol ITM call should be discounted intrinsic");

        uint256 otmCall = bs.price(80e18, 100e18, 31536000, 0, 0.05e18, false);
        assertEq(otmCall, 0, "Zero vol OTM call should be 0");
    }

    function testIntrinsicFloor() public view {
        // Deep ITM call should never price below intrinsic
        uint256 deepITM = bs.price(200e18, 100e18, 31536000, 0.2e18, 0.05e18, false);
        assertGe(deepITM, 100e18, "Deep ITM call should be at least intrinsic value");
    }

    function testPutCallParity() public view {
        // C - P = S - K·e^(-rT)
        uint256 callPrice = bs.price(100e18, 100e18, 31536000, 0.3e18, 0.05e18, false);
        uint256 putPrice = bs.price(100e18, 100e18, 31536000, 0.3e18, 0.05e18, true);
        // S - K·e^(-rT) = 100 - 100*exp(-0.05) ≈ 100 - 95.12 = 4.88
        int256 lhs = int256(callPrice) - int256(putPrice);
        assertApproxEqAbs(lhs, 4.88e18, 0.5e18, "Put-call parity should hold: C - P = S - K*exp(-rT)");
    }

    function testShortDatedOption() public view {
        // 1 hour to expiry
        uint256 price1h = bs.price(100e18, 100e18, 3600, 0.5e18, 0.05e18, false);
        // Very short dated ATM should have small but nonzero value
        assertGt(price1h, 0);
        assertLt(price1h, 5e18, "1h ATM call should be cheap");
    }
}
