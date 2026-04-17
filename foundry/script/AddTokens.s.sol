// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

import { Script, console } from "forge-std/Script.sol";
import { OptionFactory } from "../contracts/OptionFactory.sol";
import { CLOBAMM } from "../contracts/CLOBAMM.sol";
import { MockERC20 } from "../contracts/mocks/MockERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @notice Add new underlyings (AAVE, UNI) to an existing deployment.
///         Run after DeployBaseDemo without restarting anvil.
///
///         forge script script/AddTokens.s.sol --broadcast --rpc-url http://localhost:8545 \
///             --account scaffold-eth-default --password localhost --legacy \
///             --sig "run(address,address,address)" <factory> <book> <usdc>
contract AddTokens is Script {
    function run(address factoryAddr, address bookAddr, address usdcAddr) external {
        OptionFactory factory = OptionFactory(factoryAddr);
        CLOBAMM book = CLOBAMM(bookAddr);

        vm.startBroadcast();

        // 1. Deploy new tokens
        MockERC20 aave = new MockERC20("Aave", "AAVE", 18);
        MockERC20 uni  = new MockERC20("Uniswap", "UNI", 18);
        console.log("AAVE:", address(aave));
        console.log("UNI: ", address(uni));

        // 2. Create options (calls + puts against USDC)
        // AAVE ~$180 — strikes 150, 200
        address aaveCall200 = factory.createOption(address(aave), usdcAddr, uint40(block.timestamp + 7 days), 200e18, false);
        address aaveCall150 = factory.createOption(address(aave), usdcAddr, uint40(block.timestamp + 7 days), 150e18, false);
        address aavePut200  = factory.createOption(usdcAddr, address(aave), uint40(block.timestamp + 7 days), uint96(uint256(1e36) / 200e18), true);

        // UNI ~$7 — strikes 6, 8
        address uniCall8 = factory.createOption(address(uni), usdcAddr, uint40(block.timestamp + 7 days), 8e18, false);
        address uniCall6 = factory.createOption(address(uni), usdcAddr, uint40(block.timestamp + 7 days), 6e18, false);
        address uniPut8  = factory.createOption(usdcAddr, address(uni), uint40(block.timestamp + 7 days), uint96(uint256(1e36) / 8e18), true);

        console.log("AAVE Call 200:", aaveCall200);
        console.log("AAVE Call 150:", aaveCall150);
        console.log("AAVE Put 200: ", aavePut200);
        console.log("UNI Call 8:   ", uniCall8);
        console.log("UNI Call 6:   ", uniCall6);
        console.log("UNI Put 8:    ", uniPut8);

        // 3. Enable option support
        book.enableOptionSupport(aaveCall200);
        book.enableOptionSupport(aaveCall150);
        book.enableOptionSupport(aavePut200);
        book.enableOptionSupport(uniCall8);
        book.enableOptionSupport(uniCall6);
        book.enableOptionSupport(uniPut8);

        // 4. Mint + deposit
        aave.mint(msg.sender, 10_000e18);
        uni.mint(msg.sender, 100_000e18);
        MockERC20(usdcAddr).mint(msg.sender, 2_000_000e6);
        IERC20(address(aave)).approve(address(book), type(uint256).max);
        IERC20(address(uni)).approve(address(book), type(uint256).max);
        IERC20(usdcAddr).approve(address(book), type(uint256).max);
        book.deposit(address(aave), 5_000e18);
        book.deposit(address(uni), 50_000e18);
        book.deposit(usdcAddr, 1_000_000e6);

        // 5. Populate books
        // AAVE option(18dec) / USDC(6dec) premium ticks (same formula as WETH):
        //   $5→-237202  $8→-232502  $10→-230270  $15→-226215  $20→-223338  $30→-219283
        //   Bid tick = -(ask tick)

        // AAVE Call 200 (OTM ~$180 spot): cheap premium
        _a(book, aaveCall200, usdcAddr, -237202, 50e18);   // 50 @ $5
        _a(book, aaveCall200, usdcAddr, -232502, 30e18);   // 30 @ $8
        _a(book, aaveCall200, usdcAddr, -230270, 20e18);   // 20 @ $10
        _b(book, aaveCall200, usdcAddr, 239433, 60, 4);    // 60 @ $4
        _b(book, aaveCall200, usdcAddr, 242310, 100, 3);   // 100 @ $3

        // AAVE Call 150 (ITM): richer premium
        _a(book, aaveCall150, usdcAddr, -219283, 20e18);   // 20 @ $30
        _a(book, aaveCall150, usdcAddr, -216406, 15e18);   // 15 @ $40
        _a(book, aaveCall150, usdcAddr, -214175, 10e18);   // 10 @ $50
        _b(book, aaveCall150, usdcAddr, 223338, 25, 20);   // 25 @ $20
        _b(book, aaveCall150, usdcAddr, 226215, 40, 15);   // 40 @ $15

        // AAVE Put 200 (put option 6dec / USDC 6dec, raw = premium_usd)
        //   $5→16095  $8→20794  $10→23025  $3→10987  $2→6932
        _ap(book, aavePut200, usdcAddr, 16095, 10_000e6);  // @ $5
        _ap(book, aavePut200, usdcAddr, 20794, 15_000e6);  // @ $8
        _ap(book, aavePut200, usdcAddr, 23025, 8_000e6);   // @ $10
        _bp(book, aavePut200, usdcAddr, -10987, 500e6);    // @ $3
        _bp(book, aavePut200, usdcAddr, -6932, 400e6);     // @ $2

        // UNI option(18dec) / USDC(6dec) — UNI ~$7 so premiums are small
        //   $0.20→-246365  $0.30→-242310  $0.50→-237202  $0.80→-232502  $1.00→-230270
        //   $0.10→-253297  $0.15→-249242

        // UNI Call 8 (OTM): very cheap
        _a(book, uniCall8, usdcAddr, -249242, 500e18);     // 500 @ $0.15
        _a(book, uniCall8, usdcAddr, -246365, 300e18);     // 300 @ $0.20
        _a(book, uniCall8, usdcAddr, -242310, 200e18);     // 200 @ $0.30
        _b(book, uniCall8, usdcAddr, 253297, 800, 0);      // skip — too small
        // Manual bids: 600 × $0.10 = 60 USDC
        book.quote(usdcAddr, uniCall8, int24(253297), 60_000_000, false);
        book.quote(usdcAddr, uniCall8, int24(258318), 25_000_000, false); // ~$0.05

        // UNI Call 6 (ITM): more premium
        _a(book, uniCall6, usdcAddr, -237202, 200e18);     // 200 @ $0.50
        _a(book, uniCall6, usdcAddr, -232502, 150e18);     // 150 @ $0.80
        _a(book, uniCall6, usdcAddr, -230270, 100e18);     // 100 @ $1.00
        book.quote(usdcAddr, uniCall6, int24(242310), 90_000_000, false);  // ~$0.30
        book.quote(usdcAddr, uniCall6, int24(246365), 40_000_000, false);  // ~$0.20

        // UNI Put 8 (put option 6dec / USDC 6dec)
        //   $0.20→-16094  $0.30→-12039  $0.50→-6932  $0.10→-23025
        // Wait — for 6dec/6dec: raw = premium. $0.20 raw = 0.20, tick = log(0.20)/log(1.0001) = -16094
        // These are NEGATIVE ticks for < $1 premiums.
        // Actually for puts: raw = premium_usd (decimals cancel). $0.20 → tick = ln(0.20)/ln(1.0001) ≈ -16094
        _ap(book, uniPut8, usdcAddr, -16094, 5_000e6);     // @ $0.20
        _ap(book, uniPut8, usdcAddr, -12039, 8_000e6);     // @ $0.30
        _ap(book, uniPut8, usdcAddr, -6932, 3_000e6);      // @ $0.50
        _bp(book, uniPut8, usdcAddr, 23025, 1_000e6);      // @ $0.10
        _bp(book, uniPut8, usdcAddr, 29957, 500e6);        // @ $0.05

        // Fund user for testing
        aave.mint(0x5b5e727A7a78603ebF4f1652488830FC0843Df45, 100e18);
        uni.mint(0x5b5e727A7a78603ebF4f1652488830FC0843Df45, 1000e18);

        vm.stopBroadcast();
        console.log("=== AAVE + UNI added ===");
    }

    function _a(CLOBAMM bk, address opt, address cash, int24 tick, uint256 amt) internal {
        bk.quote(opt, cash, tick, amt, true);
    }
    function _b(CLOBAMM bk, address opt, address cash, int24 tick, uint256 n, uint256 usd) internal {
        if (usd == 0) return;
        bk.quote(cash, opt, tick, n * usd * 1e6, false);
    }
    function _ap(CLOBAMM bk, address opt, address cash, int24 tick, uint256 amt) internal {
        bk.quote(opt, cash, tick, amt, true);
    }
    function _bp(CLOBAMM bk, address opt, address cash, int24 tick, uint256 cashAmt) internal {
        bk.quote(cash, opt, tick, cashAmt, false);
    }
}
