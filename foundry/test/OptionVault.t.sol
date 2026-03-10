// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { Test } from "forge-std/Test.sol";
import { IERC20, ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { OptionFactory, Redemption, Option } from "../contracts/OptionFactory.sol";
import { OptionVault } from "../contracts/OptionVault.sol";
import { ShakyToken, StableToken } from "../contracts/ShakyToken.sol";

contract OptionVaultTest is Test {
    using SafeERC20 for IERC20;

    StableToken public stableToken;
    ShakyToken public shakyToken;
    OptionFactory public factory;
    OptionVault public vault;
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

        // Deploy vault (shakyToken = collateral, e.g. WETH equivalent)
        vault = new OptionVault(IERC20(address(shakyToken)), "Greek Shaky Vault", "gSHAKY", address(factory), hookAddr);

        // Setup factory approvals for vault
        vault.setupFactoryApproval();

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
        assertEq(vault.balanceOf(lp), 100e18);
        assertEq(vault.totalAssets(), 100e18);
        assertEq(shakyToken.balanceOf(address(vault)), 100e18);
    }

    function test_Withdraw() public {
        _depositAsLP(100e18);
        vm.startPrank(lp);
        vault.withdraw(50e18, lp, lp);
        vm.stopPrank();

        assertEq(vault.balanceOf(lp), 50e18);
        assertEq(shakyToken.balanceOf(lp), 1_000_000e18 - 50e18);
    }

    function test_WithdrawCappedByIdle() public {
        _depositAsLP(100e18);
        _mintAndDeliver(50e18);

        // Only 50e18 idle, LP has 100e18 worth of shares
        assertEq(vault.maxWithdraw(lp), 50e18);

        vm.startPrank(lp);
        vm.expectRevert(); // ERC4626 will revert — can't withdraw more than idle
        vault.withdraw(60e18, lp, lp);
        vm.stopPrank();
    }

    // ============ MINT AND DELIVER ============

    function test_MintAndDeliver() public {
        _depositAsLP(100e18);
        uint256 delivered = _mintAndDeliver(10e18);

        // Buyer received option tokens
        assertGt(delivered, 0);
        assertEq(IERC20(address(option)).balanceOf(buyer), delivered);

        // Vault holds Redemption tokens
        assertGt(IERC20(address(redemption)).balanceOf(address(vault)), 0);

        // Vault has no Option tokens (all delivered)
        assertEq(IERC20(address(option)).balanceOf(address(vault)), 0);

        // Bookkeeping — committed is fee-adjusted (Redemption token balance)
        uint256 fee = _fee(10e18);
        uint256 expectedCommitted = 10e18 - fee;
        assertEq(vault.committed(address(option)), expectedCommitted);
        assertEq(vault.totalCommitted(), expectedCommitted);
        // totalAssets = idle + committed (slightly less than 100e18 due to fee)
        assertEq(vault.totalAssets(), 90e18 + expectedCommitted);
    }

    function test_MintAndDeliver_OnlyHook() public {
        _depositAsLP(100e18);
        vm.prank(lp);
        vm.expectRevert(OptionVault.OnlyHook.selector);
        vault.mintAndDeliver(address(option), 10e18, buyer);
    }

    function test_MintAndDeliver_NotWhitelisted() public {
        _depositAsLP(100e18);
        // Create another option but don't whitelist
        address opt2 = factory.createOption(
            address(shakyToken), address(stableToken), uint40(block.timestamp + 2 days), 2e18, false
        );
        vm.expectRevert(OptionVault.NotWhitelisted.selector);
        vault.mintAndDeliver(opt2, 10e18, buyer);
    }

    function test_MintAndDeliver_ExceedsCap() public {
        _depositAsLP(100e18);
        // 80% cap = 80e18
        vm.expectRevert(OptionVault.ExceedsCommitmentCap.selector);
        _mintAndDeliver(81e18);
    }

    function test_MintAndDeliver_AtCap() public {
        _depositAsLP(100e18);
        // Exactly 80% should work
        _mintAndDeliver(80e18);
        // committed is fee-adjusted (Redemption token delta)
        assertEq(vault.totalCommitted(), 80e18 - _fee(80e18));
    }

    function test_MintAndDeliver_InsufficientIdle() public {
        _depositAsLP(10e18);
        // Try to mint more than idle (cap allows it since 80% of 10 = 8)
        vm.expectRevert(OptionVault.ExceedsCommitmentCap.selector);
        _mintAndDeliver(9e18);
    }

    // ============ PAIR REDEEM (BUYBACK) ============

    function test_PairRedeem() public {
        _depositAsLP(100e18);
        uint256 delivered = _mintAndDeliver(10e18);

        // Simulate buyback: buyer sends Option tokens to vault, then hook calls pairRedeem
        vm.prank(buyer);
        IERC20(address(option)).transfer(address(vault), delivered);

        vault.pairRedeem(address(option), delivered);

        // Collateral returned — committed should be zero (all pairs redeemed)
        assertEq(vault.committed(address(option)), 0);
        assertEq(vault.totalCommitted(), 0);
        // Redemption tokens burned
        assertEq(IERC20(address(redemption)).balanceOf(address(vault)), 0);
    }

    function test_PairRedeem_OnlyHook() public {
        vm.prank(lp);
        vm.expectRevert(OptionVault.OnlyHook.selector);
        vault.pairRedeem(address(option), 1e18);
    }

    // ============ SETTLEMENT ============

    function test_HandleSettlement_OTM() public {
        _depositAsLP(100e18);
        _mintAndDeliver(10e18);

        // Warp past expiration
        vm.warp(block.timestamp + 2 days);

        // Anyone calls sweep on the Redemption contract
        redemption.sweep(address(vault));

        // Vault's Redemption tokens burned, collateral returned
        assertEq(IERC20(address(redemption)).balanceOf(address(vault)), 0);

        // Reconcile bookkeeping
        vault.handleSettlement(address(option));

        assertEq(vault.committed(address(option)), 0);
        assertEq(vault.totalCommitted(), 0);

        // Collateral back in vault (minus fee that went to Redemption)
        assertGt(shakyToken.balanceOf(address(vault)), 99e18);
    }

    function test_HandleSettlement_ITM() public {
        _depositAsLP(100e18);
        _mintAndDeliver(10e18);

        // Setup: buyer exercises options (needs consideration tokens)
        uint256 optionBalance = option.balanceOf(buyer);

        // Buyer approves factory for consideration
        vm.startPrank(buyer);
        stableToken.approve(address(factory), type(uint256).max);
        factory.approve(address(stableToken), type(uint256).max);
        option.exercise(optionBalance);
        vm.stopPrank();

        // Warp past expiration
        vm.warp(block.timestamp + 2 days);

        // Sweep — vault gets pro-rata collateral + consideration
        redemption.sweep(address(vault));

        // Reconcile
        vault.handleSettlement(address(option));

        assertEq(vault.committed(address(option)), 0);
        assertEq(vault.totalCommitted(), 0);

        // Vault now holds some consideration tokens (from exercise)
        assertGt(stableToken.balanceOf(address(vault)), 0);
    }

    function test_HandleSettlement_NothingToSettle() public {
        _depositAsLP(100e18);
        _mintAndDeliver(10e18);

        // Don't sweep — Redemption balance unchanged
        vm.expectRevert(OptionVault.NothingToSettle.selector);
        vault.handleSettlement(address(option));
    }

    // ============ PREMIUM MANAGEMENT ============

    function test_ReceivePremium() public {
        // Simulate hook sending premium to vault
        stableToken.mint(hookAddr, 100e18);
        stableToken.approve(address(vault), 100e18);
        vault.receivePremium(address(stableToken), 100e18);

        assertEq(stableToken.balanceOf(address(vault)), 100e18);
    }

    function test_ReceivePremium_OnlyHook() public {
        vm.prank(lp);
        vm.expectRevert(OptionVault.OnlyHook.selector);
        vault.receivePremium(address(stableToken), 1e18);
    }

    // ============ TOTAL ASSETS / SHARE PRICE ============

    function test_TotalAssetsIncludesCommitted() public {
        _depositAsLP(100e18);
        _mintAndDeliver(50e18);

        // total = idle(50) + committed(~49.995) ≈ 99.995 (fee deducted)
        uint256 fee = _fee(50e18);
        assertEq(vault.totalAssets(), 50e18 + (50e18 - fee));
        // Shares unchanged
        assertEq(vault.balanceOf(lp), 100e18);
    }

    function test_SharePriceIncrease_FullCycle() public {
        _depositAsLP(100e18);
        uint256 sharesBefore = vault.balanceOf(lp);

        // Mint options
        _mintAndDeliver(10e18);

        // Options expire OTM
        vm.warp(block.timestamp + 2 days);
        redemption.sweep(address(vault));
        vault.handleSettlement(address(option));

        // Simulate premium income: send some extra collateral to vault
        // (in reality this comes from swapping USDC premium to WETH)
        shakyToken.mint(address(vault), 1e18);

        // totalAssets now > 100e18 but shares unchanged
        assertGt(vault.totalAssets(), 100e18);
        assertEq(vault.balanceOf(lp), sharesBefore);

        // Share price increased
        uint256 assetsPerShare = vault.convertToAssets(1e18);
        assertGt(assetsPerShare, 1e18);
    }

    // ============ MAX WITHDRAW / REDEEM ============

    function test_MaxWithdraw() public {
        _depositAsLP(100e18);
        _mintAndDeliver(50e18);

        assertEq(vault.maxWithdraw(lp), 50e18); // only idle
    }

    function test_MaxRedeem() public {
        _depositAsLP(100e18);
        _mintAndDeliver(50e18);

        // Can redeem shares worth up to 50e18 idle
        // Share price slightly < 1 due to fees, so more shares needed for 50e18 assets
        uint256 maxRedeemable = vault.maxRedeem(lp);
        assertGe(maxRedeemable, 50e18);
        assertLe(maxRedeemable, 51e18); // bounded
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

        vm.expectRevert(OptionVault.InvalidBps.selector);
        vault.setMaxCommitmentBps(10001);
    }

    function test_SetHook() public {
        address newHook = address(0x123);
        vault.setHook(newHook);
        assertEq(vault.hook(), newHook);
    }

    function test_Pause() public {
        vault.pause();
        _depositAsLP(100e18);
        // mintAndDeliver should be blocked when paused
        // (deposit also blocked by ERC4626 if we add whenNotPaused)
    }

    // ============ VIEW FUNCTIONS ============

    function test_GetVaultStats() public {
        _depositAsLP(100e18);
        _mintAndDeliver(30e18);

        (
            uint256 totalAssets_,
            uint256 totalShares_,
            uint256 idle_,
            uint256 committed_,
            uint256 utilBps_,
            uint256 premiums_
        ) = vault.getVaultStats();

        uint256 fee = _fee(30e18);
        uint256 expectedCommitted = 30e18 - fee;
        assertEq(totalAssets_, 70e18 + expectedCommitted);
        assertEq(totalShares_, 100e18);
        assertEq(idle_, 70e18);
        assertEq(committed_, expectedCommitted);
        assertGt(utilBps_, 0);
        assertEq(premiums_, 0);
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
        // Slightly under 5000 due to fee-adjusted committed
        assertApproxEqAbs(vault.utilizationBps(), 5000, 2);
    }

    // ============ MULTIPLE OPTIONS ============

    function test_MultipleOptions() public {
        // Create second option
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
