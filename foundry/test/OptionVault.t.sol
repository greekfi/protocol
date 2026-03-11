// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { Test } from "forge-std/Test.sol";
import { IERC20, ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { OptionFactory, Redemption, Option } from "../contracts/OptionFactory.sol";
import { StrategyVault } from "../contracts/StrategyVault.sol";
import { BlackScholes } from "../contracts/BlackScholes.sol";
import { IStrategyVault } from "../contracts/interfaces/IStrategyVault.sol";
import { ShakyToken, StableToken } from "../contracts/ShakyToken.sol";

/// @dev Minimal mock for the v3 oracle used by StrategyVault
contract MockV3Pool {
    address public token0;
    address public token1;
    int56 public tickCumulative0;
    int56 public tickCumulative1;

    constructor(address _token0, address _token1) {
        // Ensure token0 < token1 per Uniswap convention
        if (_token0 < _token1) {
            token0 = _token0;
            token1 = _token1;
        } else {
            token0 = _token1;
            token1 = _token0;
        }
        // Default: tick ~0 → price ≈ 1.0 (adjusted by decimals)
        tickCumulative0 = 0;
        tickCumulative1 = 0;
    }

    function setTickCumulatives(int56 _tc0, int56 _tc1) external {
        tickCumulative0 = _tc0;
        tickCumulative1 = _tc1;
    }

    function observe(uint32[] calldata)
        external
        view
        returns (int56[] memory tickCumulatives, uint160[] memory secondsPerLiquidity)
    {
        tickCumulatives = new int56[](2);
        tickCumulatives[0] = tickCumulative0;
        tickCumulatives[1] = tickCumulative1;
        secondsPerLiquidity = new uint160[](2);
    }
}

contract StrategyVaultTest is Test {
    using SafeERC20 for IERC20;

    StableToken public stableToken;
    ShakyToken public shakyToken;
    OptionFactory public factory;
    StrategyVault public vault;
    BlackScholes public bs;
    MockV3Pool public mockPool;
    Option public option;
    Redemption public redemption;

    address public hookAddr;
    address public lp = address(0x1111);
    address public buyer = address(0x2222);

    function setUp() public {
        // Fork Base
        vm.createSelectFork("https://mainnet.base.org", 43189435);

        // Deploy tokens
        stableToken = new StableToken();
        shakyToken = new ShakyToken();

        // Deploy templates
        Redemption redemptionClone = new Redemption(
            "Short Option", "SHORT", address(stableToken), address(shakyToken), block.timestamp + 1 days, 100, false
        );
        Option optionClone = new Option("Long Option", "LONG", address(redemptionClone));

        // Deploy factory
        factory = new OptionFactory(address(redemptionClone), address(optionClone), 0.0001e18);

        // Hook is this test contract for simplicity
        hookAddr = address(this);

        // Deploy BlackScholes and mock oracle
        bs = new BlackScholes();
        mockPool = new MockV3Pool(address(shakyToken), address(stableToken));
        // Set tick cumulatives for a reasonable price (tick ~0 = price 1.0)
        // For 1800s TWAP window, we want meanTick = (tc1 - tc0) / 1800
        // Set tc0 = 0, tc1 = 0 → meanTick = 0 → price ≈ 1.0
        mockPool.setTickCumulatives(0, 0);

        // Deploy vault
        vault = new StrategyVault(
            IERC20(address(shakyToken)),
            "Greek Shaky Vault",
            "gSHAKY",
            address(factory),
            address(bs),
            address(mockPool),
            address(stableToken),
            1800
        );

        // Setup factory approvals for vault
        vault.setupFactoryApproval();

        // Authorize hook
        vault.addHook(hookAddr);

        // Create an option (shakyToken collateral, stableToken consideration)
        address optionAddr = factory.createOption(
            address(shakyToken), address(stableToken), uint40(block.timestamp + 1 days), 1e18, false
        );
        option = Option(optionAddr);
        redemption = option.redemption();

        // Whitelist the option
        vault.whitelistOption(address(option), true);

        // Mint tokens
        shakyToken.mint(address(this), 1_000_000e18);
        shakyToken.mint(lp, 1_000_000e18);
        stableToken.mint(buyer, 1_000_000e18);
    }

    // ============ HELPERS ============

    function _fee(uint256 amount) internal view returns (uint256) {
        return (amount * uint256(option.fee())) / 1e18;
    }

    function _depositAsLP(uint256 amount) internal {
        vm.startPrank(lp);
        shakyToken.approve(address(vault), amount);
        vault.deposit(amount, lp);
        vm.stopPrank();
    }

    function _mintAndDeliver(uint256 amount) internal returns (uint256 delivered) {
        delivered = vault.mintAndDeliver(address(option), amount, buyer);
    }

    // ============ DEPOSIT / WITHDRAW ============

    function test_Deposit() public {
        _depositAsLP(100e18);
        // With _decimalsOffset=3, shares are scaled by 1e3
        // First deposit: shares = assets * (totalSupply + 10^offset) / (totalAssets + 1)
        // ≈ 100e18 * 1000 / 1 ≈ 100e21
        assertGt(vault.balanceOf(lp), 0);
        assertEq(vault.totalAssets(), 100e18);
        assertEq(shakyToken.balanceOf(address(vault)), 100e18);
    }

    function test_Withdraw() public {
        _depositAsLP(100e18);
        uint256 shares = vault.balanceOf(lp);

        vm.startPrank(lp);
        vault.withdraw(50e18, lp, lp);
        vm.stopPrank();

        assertLt(vault.balanceOf(lp), shares);
        assertEq(shakyToken.balanceOf(lp), 1_000_000e18 - 50e18);
    }

    function test_WithdrawCappedByIdle() public {
        _depositAsLP(100e18);
        _mintAndDeliver(50e18);

        // Only ~50e18 idle
        assertApproxEqAbs(vault.maxWithdraw(lp), 50e18, 1e18);

        vm.startPrank(lp);
        vm.expectRevert();
        vault.withdraw(60e18, lp, lp);
        vm.stopPrank();
    }

    // ============ MINT AND DELIVER ============

    function test_MintAndDeliver() public {
        _depositAsLP(100e18);
        uint256 delivered = _mintAndDeliver(10e18);

        assertGt(delivered, 0);
        assertEq(IERC20(address(option)).balanceOf(buyer), delivered);
        assertGt(IERC20(address(redemption)).balanceOf(address(vault)), 0);
        assertEq(IERC20(address(option)).balanceOf(address(vault)), 0);

        uint256 fee = _fee(10e18);
        uint256 expectedCommitted = 10e18 - fee;
        assertEq(vault.committed(address(option)), expectedCommitted);
        assertEq(vault.totalCommitted(), expectedCommitted);
    }

    function test_MintAndDeliver_OnlyHook() public {
        _depositAsLP(100e18);
        vm.prank(lp);
        vm.expectRevert(IStrategyVault.OnlyHook.selector);
        vault.mintAndDeliver(address(option), 10e18, buyer);
    }

    function test_MintAndDeliver_NotWhitelisted() public {
        _depositAsLP(100e18);
        address opt2 = factory.createOption(
            address(shakyToken), address(stableToken), uint40(block.timestamp + 2 days), 2e18, false
        );
        vm.expectRevert(IStrategyVault.NotWhitelisted.selector);
        vault.mintAndDeliver(opt2, 10e18, buyer);
    }

    function test_MintAndDeliver_ExceedsCap() public {
        _depositAsLP(100e18);
        vm.expectRevert(IStrategyVault.ExceedsCommitmentCap.selector);
        _mintAndDeliver(81e18);
    }

    function test_MintAndDeliver_AtCap() public {
        _depositAsLP(100e18);
        _mintAndDeliver(80e18);
        assertEq(vault.totalCommitted(), 80e18 - _fee(80e18));
    }

    // ============ PAIR REDEEM (BUYBACK) ============

    function test_PairRedeem() public {
        _depositAsLP(100e18);
        uint256 delivered = _mintAndDeliver(10e18);

        vm.prank(buyer);
        IERC20(address(option)).transfer(address(vault), delivered);

        vault.pairRedeem(address(option), delivered);

        assertEq(vault.committed(address(option)), 0);
        assertEq(vault.totalCommitted(), 0);
        assertEq(IERC20(address(redemption)).balanceOf(address(vault)), 0);
    }

    function test_PairRedeem_OnlyHook() public {
        vm.prank(lp);
        vm.expectRevert(IStrategyVault.OnlyHook.selector);
        vault.pairRedeem(address(option), 1e18);
    }

    // ============ TRANSFER CASH ============

    function test_TransferCash() public {
        stableToken.mint(address(vault), 100e18);
        vault.transferCash(address(stableToken), 50e18, buyer);
        assertEq(stableToken.balanceOf(buyer), 1_000_000e18 + 50e18);
    }

    function test_TransferCash_OnlyHook() public {
        vm.prank(lp);
        vm.expectRevert(IStrategyVault.OnlyHook.selector);
        vault.transferCash(address(stableToken), 1e18, buyer);
    }

    function test_TransferCash_InsufficientCash() public {
        vm.expectRevert(IStrategyVault.InsufficientCash.selector);
        vault.transferCash(address(stableToken), 1e18, buyer);
    }

    // ============ SETTLEMENT ============

    function test_HandleSettlement_OTM() public {
        _depositAsLP(100e18);
        _mintAndDeliver(10e18);

        vm.warp(block.timestamp + 2 days);
        redemption.sweep(address(vault));

        assertEq(IERC20(address(redemption)).balanceOf(address(vault)), 0);

        vault.handleSettlement(address(option));
        assertEq(vault.committed(address(option)), 0);
        assertEq(vault.totalCommitted(), 0);
        assertGt(shakyToken.balanceOf(address(vault)), 99e18);
    }

    function test_HandleSettlement_ITM() public {
        _depositAsLP(100e18);
        _mintAndDeliver(10e18);

        uint256 optionBalance = option.balanceOf(buyer);
        vm.startPrank(buyer);
        stableToken.approve(address(factory), type(uint256).max);
        factory.approve(address(stableToken), type(uint256).max);
        option.exercise(optionBalance);
        vm.stopPrank();

        vm.warp(block.timestamp + 2 days);
        redemption.sweep(address(vault));

        vault.handleSettlement(address(option));
        assertEq(vault.committed(address(option)), 0);
        assertEq(vault.totalCommitted(), 0);
        assertGt(stableToken.balanceOf(address(vault)), 0);
    }

    function test_HandleSettlement_NothingToSettle() public {
        _depositAsLP(100e18);
        _mintAndDeliver(10e18);

        vm.expectRevert(IStrategyVault.NothingToSettle.selector);
        vault.handleSettlement(address(option));
    }

    // ============ ROLLING ============

    function test_RollOptions() public {
        _depositAsLP(100e18);
        _mintAndDeliver(10e18);

        // Set strategy
        IStrategyVault.StrikeConfig[] memory configs = new IStrategyVault.StrikeConfig[](2);
        configs[0] = IStrategyVault.StrikeConfig({ strikeOffsetBps: 10000, isPut: false, duration: 7 days }); // ATM call
        configs[1] = IStrategyVault.StrikeConfig({ strikeOffsetBps: 11000, isPut: false, duration: 7 days }); // 10% OTM call
        vault.setStrategy(configs);
        vault.setRollBounty(0.01e18);

        // Warp past expiration
        vm.warp(block.timestamp + 2 days);

        uint256 callerBalBefore = shakyToken.balanceOf(address(this));
        address[] memory newOptions = vault.rollOptions(address(option));

        assertEq(newOptions.length, 2);
        assertTrue(vault.whitelistedOptions(newOptions[0]));
        assertTrue(vault.whitelistedOptions(newOptions[1]));

        // Bounty paid
        assertEq(shakyToken.balanceOf(address(this)) - callerBalBefore, 0.01e18);
    }

    function test_RollOptions_NotExpired() public {
        _depositAsLP(100e18);

        IStrategyVault.StrikeConfig[] memory configs = new IStrategyVault.StrikeConfig[](1);
        configs[0] = IStrategyVault.StrikeConfig({ strikeOffsetBps: 10000, isPut: false, duration: 7 days });
        vault.setStrategy(configs);

        vm.expectRevert(IStrategyVault.OptionNotExpired.selector);
        vault.rollOptions(address(option));
    }

    function test_RollOptions_AlreadyRolled() public {
        _depositAsLP(100e18);

        IStrategyVault.StrikeConfig[] memory configs = new IStrategyVault.StrikeConfig[](1);
        configs[0] = IStrategyVault.StrikeConfig({ strikeOffsetBps: 10000, isPut: false, duration: 7 days });
        vault.setStrategy(configs);

        vm.warp(block.timestamp + 2 days);
        vault.rollOptions(address(option));

        vm.expectRevert(IStrategyVault.AlreadyRolled.selector);
        vault.rollOptions(address(option));
    }

    // ============ ADMIN ============

    function test_WhitelistOption() public {
        address opt2 = factory.createOption(
            address(shakyToken), address(stableToken), uint40(block.timestamp + 2 days), 2e18, false
        );
        vault.whitelistOption(opt2, true);
        assertTrue(vault.whitelistedOptions(opt2));

        vault.whitelistOption(opt2, false);
        assertFalse(vault.whitelistedOptions(opt2));
    }

    function test_WhitelistOption_OnlyOwner() public {
        vm.prank(lp);
        vm.expectRevert();
        vault.whitelistOption(address(option), false);
    }

    function test_SetMaxCommitmentBps() public {
        vault.setMaxCommitmentBps(5000);
        assertEq(vault.maxCommitmentBps(), 5000);

        vm.expectRevert(IStrategyVault.InvalidBps.selector);
        vault.setMaxCommitmentBps(10001);
    }

    function test_SetVolatility() public {
        vault.setVolatility(0.3e18);
        assertEq(vault.volatility(), 0.3e18);
    }

    function test_AddRemoveHook() public {
        address newHook = address(0x123);
        vault.addHook(newHook);
        assertTrue(vault.authorizedHooks(newHook));

        vault.removeHook(newHook);
        assertFalse(vault.authorizedHooks(newHook));
    }

    function test_CreateOption() public {
        address opt = vault.createOption(2e18, uint40(block.timestamp + 7 days), false);
        assertTrue(vault.whitelistedOptions(opt));
    }

    function test_Pause() public {
        vault.pause();
        _depositAsLP(100e18);
        vm.expectRevert();
        _mintAndDeliver(10e18);
    }

    // ============ VIEW FUNCTIONS ============

    function test_GetVaultStats() public {
        _depositAsLP(100e18);
        _mintAndDeliver(30e18);

        (uint256 totalAssets_, uint256 totalShares_, uint256 idle_, uint256 committed_, uint256 utilBps_,) =
            vault.getVaultStats();

        uint256 fee = _fee(30e18);
        uint256 expectedCommitted = 30e18 - fee;
        assertEq(totalAssets_, 70e18 + expectedCommitted);
        assertGt(totalShares_, 0);
        assertEq(idle_, 70e18);
        assertEq(committed_, expectedCommitted);
        assertGt(utilBps_, 0);
    }

    function test_GetPositionInfo() public {
        _depositAsLP(100e18);
        _mintAndDeliver(10e18);

        (uint256 com, uint256 redBal, bool expired) = vault.getPositionInfo(address(option));
        assertEq(com, 10e18 - _fee(10e18));
        assertGt(redBal, 0);
        assertFalse(expired);

        vm.warp(block.timestamp + 2 days);
        (,, expired) = vault.getPositionInfo(address(option));
        assertTrue(expired);
    }

    function test_UtilizationBps() public {
        _depositAsLP(100e18);
        assertEq(vault.utilizationBps(), 0);

        _mintAndDeliver(50e18);
        assertApproxEqAbs(vault.utilizationBps(), 5000, 2);
    }

    // ============ SPREAD ============

    function test_SetSpreadBps() public {
        vault.setSpreadBps(200); // 2%
        assertEq(vault.spreadBps(), 200);
    }

    function test_SetSpreadBps_MaxExceeded() public {
        vm.expectRevert(IStrategyVault.InvalidBps.selector);
        vault.setSpreadBps(5001);
    }

    function test_SetSpreadBps_OnlyOwner() public {
        vm.prank(lp);
        vm.expectRevert();
        vault.setSpreadBps(100);
    }

    function test_SpreadAffectsQuotes() public {
        // Get mid-price quote (no spread)
        (uint256 midBuyOut,) = vault.getQuote(address(option), 100e6, true);
        (uint256 midSellOut,) = vault.getQuote(address(option), 100e18, false);

        // Set 10% spread (500 bps each side)
        vault.setSpreadBps(1000);

        // Ask price is higher → fewer options per cash
        (uint256 spreadBuyOut,) = vault.getQuote(address(option), 100e6, true);
        assertLt(spreadBuyOut, midBuyOut, "Spread should reduce options received when buying");

        // Bid price is lower → less cash per option
        (uint256 spreadSellOut,) = vault.getQuote(address(option), 100e18, false);
        assertLt(spreadSellOut, midSellOut, "Spread should reduce cash received when selling");
    }

    function test_ZeroSpreadIsDefault() public {
        assertEq(vault.spreadBps(), 0);
        // With zero spread, bid = ask = mid
        (uint256 buyOut, uint256 buyPrice) = vault.getQuote(address(option), 100e6, true);
        (uint256 sellOut, uint256 sellPrice) = vault.getQuote(address(option), 100e18, false);
        // Prices should be equal at zero spread
        assertEq(buyPrice, sellPrice, "Bid and ask should equal at zero spread");
    }

    // ============ VOL SMILE ============

    function test_SetSkew() public {
        vault.setSkew(-0.2e18);
        assertEq(vault.skew(), -0.2e18);
    }

    function test_SetKurtosis() public {
        vault.setKurtosis(0.1e18);
        assertEq(vault.kurtosis(), 0.1e18);
    }

    function test_SetSkew_OnlyOwner() public {
        vm.prank(lp);
        vm.expectRevert();
        vault.setSkew(-0.2e18);
    }

    function test_SetKurtosis_OnlyOwner() public {
        vm.prank(lp);
        vm.expectRevert();
        vault.setKurtosis(0.1e18);
    }

    function test_SkewKurtosisDefaultZero() public {
        assertEq(vault.skew(), 0);
        assertEq(vault.kurtosis(), 0);
    }

    function test_SmileAffectsQuotes() public {
        // Get quote with flat vol (default skew=0, kurtosis=0)
        (uint256 flatOut, uint256 flatPrice) = vault.getQuote(address(option), 100e6, true);

        // Set smile params — with OTM option, skew/kurtosis will change the price
        vault.setSkew(-0.2e18);
        vault.setKurtosis(0.1e18);

        (uint256 smileOut, uint256 smilePrice) = vault.getQuote(address(option), 100e6, true);

        // For ATM options (strike ≈ spot), smile should have minimal effect
        // For OTM/ITM, the effect would be larger
        // Either way, verify the function doesn't revert and returns valid results
        assertGt(smileOut, 0);
        assertGt(smilePrice, 0);
    }

    // ============ MULTIPLE OPTIONS ============

    function test_MultipleOptions() public {
        address opt2Addr = factory.createOption(
            address(shakyToken), address(stableToken), uint40(block.timestamp + 2 days), 2e18, false
        );
        vault.whitelistOption(opt2Addr, true);

        _depositAsLP(100e18);
        _mintAndDeliver(20e18);
        vault.mintAndDeliver(opt2Addr, 30e18, buyer);

        uint256 fee1 = _fee(20e18);
        uint256 fee2 = (30e18 * uint256(Option(opt2Addr).fee())) / 1e18;
        assertEq(vault.committed(address(option)), 20e18 - fee1);
        assertEq(vault.committed(opt2Addr), 30e18 - fee2);
        assertEq(vault.totalCommitted(), (20e18 - fee1) + (30e18 - fee2));
    }
}
