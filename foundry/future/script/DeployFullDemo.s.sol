// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

import { Script, console } from "forge-std/Script.sol";
import { Factory } from "../contracts/Factory.sol";
import { Option } from "../contracts/Option.sol";
import { Collateral } from "../contracts/Collateral.sol";
import { CLOBAMM } from "../contracts/CLOBAMM.sol";
import { MockERC20 } from "../contracts/mocks/MockERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @notice Complete demo: 4 underlyings × 3 strikes × 4 expiries × call+put = 96 options.
///         All populated with varied liquidity.
///
///         anvil --fork-url https://mainnet.base.org --chain-id 31337
///         forge script script/DeployFullDemo.s.sol --broadcast --rpc-url http://localhost:8545 \
///             --account scaffold-eth-default --password localhost --legacy
contract DeployFullDemo is Script {
    address user = 0x5b5e727A7a78603ebF4f1652488830FC0843Df45;

    // Expiry offsets
    uint40[4] EXPIRIES = [uint40(7 days), uint40(14 days), uint40(30 days), uint40(90 days)];

    function run() external {
        vm.startBroadcast();

        // ===== 1. Tokens =====
        MockERC20 weth = new MockERC20("Wrapped Ether", "WETH", 18);
        MockERC20 usdc = new MockERC20("USD Coin", "USDC", 6);
        MockERC20 wbtc = new MockERC20("Wrapped BTC", "WBTC", 8);
        MockERC20 aave = new MockERC20("Aave", "AAVE", 18);
        MockERC20 uni = new MockERC20("Uniswap", "UNI", 18);

        // ===== 2. Protocol =====
        Collateral coll = new Collateral("C", "C");
        Option opt = new Option("O", "O");
        Factory factory = new Factory(address(coll), address(opt));
        CLOBAMM book = new CLOBAMM();

        console.log("Factory:", address(factory));
        console.log("Book:   ", address(book));
        console.log("WETH:", address(weth));
        console.log("USDC:", address(usdc));
        console.log("WBTC:", address(wbtc));
        console.log("AAVE:", address(aave));
        console.log("UNI: ", address(uni));

        // ===== 3. Create all options =====
        // Struct: (collateral, consideration, strikes[])
        // Calls: collateral=underlying, consideration=USDC
        // Puts: collateral=USDC, consideration=underlying, strike=inverted

        address[4] memory underlyings = [address(weth), address(wbtc), address(aave), address(uni)];
        // Strikes per underlying (in USDC terms for calls)
        uint256[3][4] memory strikes = [
            [uint256(2500e18), uint256(3000e18), uint256(3500e18)], // WETH
            [uint256(60000e18), uint256(80000e18), uint256(100000e18)], // WBTC
            [uint256(150e18), uint256(200e18), uint256(250e18)], // AAVE
            [uint256(5e18), uint256(7e18), uint256(10e18)] // UNI
        ];

        // Create + enable all options
        address[] memory allOptions = new address[](96); // 4 underlyings × 3 strikes × 4 expiries × 2 sides
        uint256 idx;
        for (uint256 u = 0; u < 4; u++) {
            for (uint256 s = 0; s < 3; s++) {
                for (uint256 e = 0; e < 4; e++) {
                    uint40 exp = uint40(block.timestamp) + EXPIRIES[e];
                    // Call
                    address c = factory.createOption(underlyings[u], address(usdc), exp, uint96(strikes[u][s]), false);
                    book.enableOptionSupport(c);
                    allOptions[idx++] = c;
                    // Put (strike inverted)
                    uint96 putStrike = uint96(uint256(1e36) / strikes[u][s]);
                    address p = factory.createOption(address(usdc), underlyings[u], exp, putStrike, true);
                    book.enableOptionSupport(p);
                    allOptions[idx++] = p;
                }
            }
        }
        console.log("Created", idx, "options");

        // ===== 4. Fund + deposit =====
        weth.mint(msg.sender, 1000e18);
        wbtc.mint(msg.sender, 200e8);
        aave.mint(msg.sender, 50_000e18);
        uni.mint(msg.sender, 500_000e18);
        usdc.mint(msg.sender, 20_000_000e6);

        IERC20(address(weth)).approve(address(book), type(uint256).max);
        IERC20(address(wbtc)).approve(address(book), type(uint256).max);
        IERC20(address(aave)).approve(address(book), type(uint256).max);
        IERC20(address(uni)).approve(address(book), type(uint256).max);
        IERC20(address(usdc)).approve(address(book), type(uint256).max);

        book.deposit(address(weth), 500e18);
        book.deposit(address(wbtc), 100e8);
        book.deposit(address(aave), 20_000e18);
        book.deposit(address(uni), 200_000e18);
        book.deposit(address(usdc), 10_000_000e6);

        // ===== 5. Seed liquidity =====
        // For each option, post 3 asks + 2 bids at varied premiums.
        // Premium ticks scale by the option's moneyness + time.
        idx = 0;
        for (uint256 u = 0; u < 4; u++) {
            uint8 optDec = MockERC20(underlyings[u]).decimals();
            for (uint256 s = 0; s < 3; s++) {
                for (uint256 e = 0; e < 4; e++) {
                    // Call
                    _seedCall(book, allOptions[idx], address(usdc), optDec, u, s, e);
                    idx++;
                    // Put
                    _seedPut(book, allOptions[idx], address(usdc), u, s, e);
                    idx++;
                }
            }
        }

        // ===== 6. Fund user =====
        weth.mint(user, 100e18);
        wbtc.mint(user, 10e8);
        aave.mint(user, 500e18);
        uni.mint(user, 5000e18);
        usdc.mint(user, 500_000e6);

        vm.stopBroadcast();
        console.log("=== Full Demo Deployed ===");
    }

    // Premium tick tables indexed by [moneyness][timeIndex]
    // moneyness: 0=ITM, 1=ATM, 2=OTM
    // For 18dec option / 6dec USDC:
    //   premiums(USD): ITM=[300,350,500,800] ATM=[80,100,150,250] OTM=[10,15,25,50]
    //   ticks computed as log(premium * 1e6 / 1e18) / log(1.0001)
    int24[4][3] ASK_TICKS_18 = [
        [int24(-219283), int24(-217716), int24(-214175), int24(-209475)], // ITM: $300,$350,$500,$800
        [int24(-232502), int24(-230270), int24(-226215), int24(-223338)], // ATM: $80,$100,$150,$200
        [int24(-253297), int24(-249242), int24(-246365), int24(-237202)] // OTM: $10,$15,$20,$50
    ];
    // For 8dec option / 6dec USDC (WBTC):
    //   raw = premium * 1e6 / 1e8 = premium * 0.01
    //   ticks are POSITIVE for large premiums
    int24[4][3] ASK_TICKS_8 = [
        [int24(29957), int24(31541), int24(34012), int24(37740)], // ITM: $2000,$2500,$3000,$5000 (raw 20,25,30,50)
        [int24(20794), int24(23025), int24(26593), int24(29957)], // ATM: $800,$1000,$1500,$2000
        [int24(10987), int24(13862), int24(16095), int24(20794)] // OTM: $300,$400,$500,$800
    ];
    // Amounts per moneyness (in option-wei, will be scaled by decimals)
    uint256[3] CALL_SIZES = [uint256(5), uint256(10), uint256(20)]; // fewer ITM, more OTM

    // Put premiums: option is 6dec, cash is 6dec → raw = premium_usd, tick = log(premium)/log(1.0001)
    int24[4][3] ASK_TICKS_PUT = [
        [int24(34014), int24(35607), int24(39122), int24(43822)], // ITM: $30,$35,$50,$80
        [int24(20794), int24(23025), int24(26593), int24(29957)], // ATM: $8,$10,$15,$20
        [int24(6932), int24(10987), int24(13862), int24(16095)] // OTM: $2,$3,$4,$5
    ];

    function _seedCall(CLOBAMM bk, address opt, address cash, uint8 optDec, uint256 u, uint256 s, uint256 e) internal {
        int24[4][3] storage ticks = optDec == 8 ? ASK_TICKS_8 : ASK_TICKS_18;
        int24 askTick = ticks[s][e];
        // Scale sizes by decimals
        uint256 base = CALL_SIZES[s] * (10 ** optDec);
        // 3 ask levels: at premium, +5%, +12%
        bk.quote(opt, cash, askTick, base, true);
        bk.quote(opt, cash, askTick + 487, base * 80 / 100, true); // ~5% higher
        bk.quote(opt, cash, askTick + 1133, base * 50 / 100, true); // ~12% higher
        // 2 bid levels: -5%, -15% from ask
        int24 bidTick1 = -(askTick - 513); // ~5% cheaper
        int24 bidTick2 = -(askTick - 1625); // ~15% cheaper
        uint256 bidCash1 = _premiumFromTick(askTick - 513, optDec) * base / (10 ** optDec) * 80 / 100;
        uint256 bidCash2 = _premiumFromTick(askTick - 1625, optDec) * base / (10 ** optDec) * 120 / 100;
        if (bidCash1 > 0) bk.quote(cash, opt, bidTick1, bidCash1, false);
        if (bidCash2 > 0) bk.quote(cash, opt, bidTick2, bidCash2, false);
    }

    function _seedPut(CLOBAMM bk, address opt, address cash, uint256 u, uint256 s, uint256 e) internal {
        int24 askTick = ASK_TICKS_PUT[s][e];
        // Put amounts in 6dec (USDC-collateral). Scale: ITM=5000, ATM=20000, OTM=50000
        uint256[3] memory putSizes = [uint256(5_000e6), uint256(20_000e6), uint256(50_000e6)];
        uint256 base = putSizes[s];
        bk.quote(opt, cash, askTick, base, true);
        bk.quote(opt, cash, askTick + 487, base * 80 / 100, true);
        bk.quote(opt, cash, askTick + 1133, base * 50 / 100, true);
        // Bids
        int24 bidTick1 = -(askTick - 513);
        int24 bidTick2 = -(askTick - 1625);
        // For puts, bid cash amount is small fractions
        uint256 bidAmt1 = base * 60 / 100 / 10; // rough premium fraction
        uint256 bidAmt2 = base * 40 / 100 / 10;
        if (bidAmt1 > 0) bk.quote(cash, opt, bidTick1, bidAmt1, false);
        if (bidAmt2 > 0) bk.quote(cash, opt, bidTick2, bidAmt2, false);
    }

    /// @dev Approximate premium in USDC-wei from a tick (for bid sizing)
    function _premiumFromTick(int24 tick, uint8 optDec) internal pure returns (uint256) {
        // Very rough: premium_usd ≈ 1.0001^tick * 10^(optDec - 6)
        // We just need order-of-magnitude for bid sizing
        // For simplicity return a fixed reasonable amount based on tick sign
        if (tick < -240000) return 10e6; // ~$10
        if (tick < -230000) return 80e6; // ~$80
        if (tick < -220000) return 200e6; // ~$200
        if (tick < -210000) return 500e6; // ~$500
        if (tick < -200000) return 1000e6; // ~$1000
        if (tick < 0) return 5000e6; // ~$5000
        if (tick < 15000) return 5e6; // ~$5
        if (tick < 25000) return 50e6; // ~$50
        if (tick < 35000) return 500e6; // ~$500
        return 2000e6; // ~$2000
    }
}
