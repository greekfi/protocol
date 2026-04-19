// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

import { Script, console } from "forge-std/Script.sol";
import { Factory } from "../contracts/Factory.sol";
import { Collateral } from "../contracts/Collateral.sol";
import { Option } from "../contracts/Option.sol";
import { CLOBAMM } from "../contracts/CLOBAMM.sol";
import { MockERC20 } from "../contracts/mocks/MockERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @notice Full demo on a forked Base chain: deploy factory + CLOBAMM, create WETH/USDC + BTC/USDC
///         options using mintable token mocks that match real decimal counts.
///
///         anvil --fork-url https://mainnet.base.org --chain-id 31337
///         forge script script/DeployBaseDemo.s.sol --broadcast --rpc-url http://localhost:8545 \
///             --account scaffold-eth-default --password localhost --legacy
contract DeployBaseDemo is Script {
    function run() external {
        vm.startBroadcast();

        // 1. Deploy mintable token mocks with real-world decimals
        MockERC20 weth = new MockERC20("Wrapped Ether", "WETH", 18);
        MockERC20 usdc = new MockERC20("USD Coin", "USDC", 6);
        MockERC20 wbtc = new MockERC20("Wrapped BTC", "WBTC", 8);
        console.log("WETH:", address(weth));
        console.log("USDC:", address(usdc));
        console.log("WBTC:", address(wbtc));

        // 2. Deploy protocol
        Collateral collClone = new Collateral("Collateral", "COLL");
        Option optionClone = new Option("Option", "OPT");
        Factory factory = new Factory(address(collClone), address(optionClone));
        CLOBAMM book = new CLOBAMM();
        console.log("Factory:", address(factory));
        console.log("CLOBAMM:      ", address(book));

        // 3. Create WETH/USDC options
        address ethCall3k_7d =
            factory.createOption(address(weth), address(usdc), uint40(block.timestamp + 7 days), 3000e18, false);
        address ethCall3k_30d =
            factory.createOption(address(weth), address(usdc), uint40(block.timestamp + 30 days), 3000e18, false);
        address ethCall3500 =
            factory.createOption(address(weth), address(usdc), uint40(block.timestamp + 7 days), 3500e18, false);
        address ethCall2500 =
            factory.createOption(address(weth), address(usdc), uint40(block.timestamp + 7 days), 2500e18, false);

        // WETH puts (collateral=USDC, consideration=WETH)
        uint96 putStrike3k = uint96(uint256(1e36) / 3000e18);
        address ethPut3k =
            factory.createOption(address(usdc), address(weth), uint40(block.timestamp + 7 days), putStrike3k, true);
        uint96 putStrike2500 = uint96(uint256(1e36) / 2500e18);
        address ethPut2500 =
            factory.createOption(address(usdc), address(weth), uint40(block.timestamp + 7 days), putStrike2500, true);

        // WBTC/USDC calls
        address btcCall80k =
            factory.createOption(address(wbtc), address(usdc), uint40(block.timestamp + 7 days), 80000e18, false);
        address btcCall100k =
            factory.createOption(address(wbtc), address(usdc), uint40(block.timestamp + 7 days), 100000e18, false);

        console.log("ETH Call 3k 7d: ", ethCall3k_7d);
        console.log("ETH Call 3k 30d:", ethCall3k_30d);
        console.log("ETH Call 3.5k:  ", ethCall3500);
        console.log("ETH Call 2.5k:  ", ethCall2500);
        console.log("ETH Put 3k:     ", ethPut3k);
        console.log("ETH Put 2.5k:   ", ethPut2500);
        console.log("BTC Call 80k:   ", btcCall80k);
        console.log("BTC Call 100k:  ", btcCall100k);

        // 4. Enable option support
        book.enableOptionSupport(ethCall3k_7d);
        book.enableOptionSupport(ethCall3k_30d);
        book.enableOptionSupport(ethCall3500);
        book.enableOptionSupport(ethCall2500);
        book.enableOptionSupport(ethPut3k);
        book.enableOptionSupport(ethPut2500);
        book.enableOptionSupport(btcCall80k);
        book.enableOptionSupport(btcCall100k);

        // 5. Mint + deposit
        weth.mint(msg.sender, 500e18);
        usdc.mint(msg.sender, 5_000_000e6);
        wbtc.mint(msg.sender, 100e8);
        IERC20(address(weth)).approve(address(book), type(uint256).max);
        IERC20(address(usdc)).approve(address(book), type(uint256).max);
        IERC20(address(wbtc)).approve(address(book), type(uint256).max);
        book.deposit(address(weth), 200e18);
        book.deposit(address(usdc), 2_000_000e6);
        book.deposit(address(wbtc), 20e8);

        // 6. Populate WETH/USDC books
        // Tick ref (USDC 6dec / WETH-option 18dec):
        //   $50→-237202  $80→-232502  $100→-230270  $120→-228447  $150→-226215
        //   $200→-223338  $300→-219283  $500→-214175  $800→-209475  $1000→-207243
        //   $10→-253297  $15→-249242  $20→-246365  $30→-242310  $40→-239433
        //   $60→-235379    Bid tick = -(ask tick)

        _a(book, ethCall3k_7d, address(usdc), -232502, 5e18);
        _a(book, ethCall3k_7d, address(usdc), -230270, 10e18);
        _a(book, ethCall3k_7d, address(usdc), -228447, 8e18);
        _a(book, ethCall3k_7d, address(usdc), -226215, 3e18);
        _b(book, ethCall3k_7d, address(usdc), 235379, 8, 60);
        _b(book, ethCall3k_7d, address(usdc), 237202, 12, 50);
        _b(book, ethCall3k_7d, address(usdc), 242310, 20, 30);

        _a(book, ethCall3k_30d, address(usdc), -226215, 4e18);
        _a(book, ethCall3k_30d, address(usdc), -223338, 8e18);
        _a(book, ethCall3k_30d, address(usdc), -219283, 12e18);
        _b(book, ethCall3k_30d, address(usdc), 228447, 6, 120);
        _b(book, ethCall3k_30d, address(usdc), 230270, 10, 100);
        _b(book, ethCall3k_30d, address(usdc), 232502, 15, 80);

        _a(book, ethCall3500, address(usdc), -246365, 10e18);
        _a(book, ethCall3500, address(usdc), -242310, 8e18);
        _a(book, ethCall3500, address(usdc), -237202, 5e18);
        _b(book, ethCall3500, address(usdc), 249242, 12, 15);
        _b(book, ethCall3500, address(usdc), 253297, 20, 10);

        _a(book, ethCall2500, address(usdc), -214175, 3e18);
        _a(book, ethCall2500, address(usdc), -209475, 6e18);
        _a(book, ethCall2500, address(usdc), -207243, 4e18);
        _b(book, ethCall2500, address(usdc), 216406, 5, 400);
        _b(book, ethCall2500, address(usdc), 219283, 8, 300);
        _b(book, ethCall2500, address(usdc), 223338, 10, 200);

        // ETH Put 3k (option dec = 6, cash dec = 6 → raw = premium_usd, decimals cancel)
        //   $80→43822  $100→46054  $120→47877  $50→39122  $30→34014
        //   Bid tick = -(ask tick)
        _a(book, ethPut3k, address(usdc), 43822, 30_000e6); // 30k puts @ $80
        _a(book, ethPut3k, address(usdc), 46054, 50_000e6); // 50k puts @ $100
        _a(book, ethPut3k, address(usdc), 47877, 20_000e6); // 20k puts @ $120
        _bp(book, ethPut3k, address(usdc), -39122, 1_250e6); // @ $50
        _bp(book, ethPut3k, address(usdc), -34014, 1_200e6); // @ $30

        // ETH Put 2.5k
        //   $50→39122  $60→40945  $80→43822  $40→36891  $30→34014
        _a(book, ethPut2500, address(usdc), 39122, 20_000e6); // @ $50
        _a(book, ethPut2500, address(usdc), 40945, 40_000e6); // @ $60
        _a(book, ethPut2500, address(usdc), 43822, 15_000e6); // @ $80
        _bp(book, ethPut2500, address(usdc), -36891, 1_600e6); // @ $40
        _bp(book, ethPut2500, address(usdc), -34014, 900e6); // @ $30

        // BTC Call 80k (option dec = 8). Raw premium = $ * 1e6 / 1e8 = $ * 0.01
        //   $800→tick 20794  $1000→23025  $2000→29957  $3000→34012  $5000→39120  $500→16095  $300→10987
        _a(book, btcCall80k, address(usdc), 29957, 2e8);
        _a(book, btcCall80k, address(usdc), 34012, 3e8);
        _a(book, btcCall80k, address(usdc), 39120, 1e8);
        _b8(book, btcCall80k, address(usdc), -23025, 3, 1000);
        _b8(book, btcCall80k, address(usdc), -20794, 5, 800);

        // BTC Call 100k
        _a(book, btcCall100k, address(usdc), 20794, 5e8);
        _a(book, btcCall100k, address(usdc), 23025, 3e8);
        _a(book, btcCall100k, address(usdc), 29957, 2e8);
        _b8(book, btcCall100k, address(usdc), -16095, 8, 500);
        _b8(book, btcCall100k, address(usdc), -10987, 10, 300);

        // Fund another account for testing
        weth.mint(0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266, 100e18);
        usdc.mint(0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266, 500_000e6);

        vm.stopBroadcast();
        console.log("=== Base Demo Deployed + Populated ===");
    }

    function _a(CLOBAMM bk, address opt, address cash, int24 tick, uint256 amt) internal {
        bk.quote(opt, cash, tick, amt, true);
    }

    function _b(CLOBAMM bk, address opt, address cash, int24 tick, uint256 n, uint256 usd) internal {
        bk.quote(cash, opt, tick, n * usd * 1e6, false);
    }

    function _bp(CLOBAMM bk, address opt, address cash, int24 tick, uint256 cashAmt) internal {
        bk.quote(cash, opt, tick, cashAmt, false);
    }

    // BTC bids: numOptions is whole BTC-options, price in USD
    function _b8(CLOBAMM bk, address opt, address cash, int24 tick, uint256 n, uint256 usd) internal {
        bk.quote(cash, opt, tick, n * usd * 1e6, false);
    }
}
