// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { Test } from "forge-std/Test.sol";
import { IERC20, ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { OptionFactory, Redemption, Option } from "../contracts/OptionFactory.sol";
import { YieldVault } from "../contracts/YieldVault.sol";
import { BlackScholes } from "../contracts/BlackScholes.sol";
import { IYieldVault } from "../contracts/interfaces/IYieldVault.sol";
import { IERC7540Redeem, IERC7540Operator } from "../contracts/interfaces/IERC7540.sol";
import { IERC1271 } from "@openzeppelin/contracts/interfaces/IERC1271.sol";
import { ShakyToken, StableToken } from "../contracts/ShakyToken.sol";

/// @dev Simulates Bebop's settlement: validates EIP-1271 signature, pulls options from taker, sends USDC
contract MockBebopSettlement {
    using SafeERC20 for IERC20;

    address public balanceManager;

    constructor() {
        balanceManager = address(this); // self acts as balance manager for simplicity
    }

    /// @dev Simulates settleInternal: validate taker sig, pull sell tokens, send buy tokens
    function mockSettle(
        address taker,
        address sellToken,
        uint256 sellAmount,
        address buyToken,
        uint256 buyAmount,
        bytes32 orderHash,
        bytes calldata signature
    ) external {
        // Step 1: Validate taker signature via EIP-1271 (same as JamValidation.validateSignature)
        if (taker.code.length > 0) {
            bytes4 magic = IERC1271(taker).isValidSignature(orderHash, signature);
            require(magic == 0x1626ba7e, "Invalid contract signature");
        }

        // Step 2: Pull sell tokens (options) from taker → this contract
        IERC20(sellToken).safeTransferFrom(taker, msg.sender, sellAmount);

        // Step 3: Send buy tokens (USDC) from solver (msg.sender) → taker
        IERC20(buyToken).safeTransferFrom(msg.sender, taker, buyAmount);
    }
}

/// @dev Minimal mock for the v3 oracle used by YieldVault
contract MockV3Pool {
    address public token0;
    address public token1;
    int56 public tickCumulative0;
    int56 public tickCumulative1;

    constructor(address _token0, address _token1) {
        if (_token0 < _token1) {
            token0 = _token0;
            token1 = _token1;
        } else {
            token0 = _token1;
            token1 = _token0;
        }
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

contract YieldVaultTest is Test {
    using SafeERC20 for IERC20;

    StableToken public stableToken;
    ShakyToken public shakyToken;
    OptionFactory public factory;
    YieldVault public vault;
    BlackScholes public bs;
    MockV3Pool public mockPool;
    Option public option;
    Redemption public redemption;

    address public hookAddr;
    address public lp = address(0x1111);
    address public buyer = address(0x2222);
    uint256 public operatorPk = 0xA11CE;
    address public operator;

    function setUp() public {
        vm.createSelectFork("https://mainnet.base.org", 43189435);

        stableToken = new StableToken();
        shakyToken = new ShakyToken();

        Redemption redemptionClone = new Redemption(
            "Short Option", "SHORT", address(stableToken), address(shakyToken), block.timestamp + 1 days, 100, false
        );
        Option optionClone = new Option("Long Option", "LONG", address(redemptionClone));

        factory = new OptionFactory(address(redemptionClone), address(optionClone), 0.0001e18);

        hookAddr = address(this);

        bs = new BlackScholes();
        mockPool = new MockV3Pool(address(shakyToken), address(stableToken));
        mockPool.setTickCumulatives(0, 0);

        vault = new YieldVault(
            IERC20(address(shakyToken)),
            "Greek Shaky Vault",
            "gSHAKY",
            address(factory),
            address(bs),
            address(mockPool),
            address(stableToken),
            1800
        );

        vault.setupFactoryApproval();
        vault.addHook(hookAddr);

        address optionAddr = factory.createOption(
            address(shakyToken), address(stableToken), uint40(block.timestamp + 1 days), 1e18, false
        );
        option = Option(optionAddr);
        redemption = option.redemption();

        vault.whitelistOption(address(option), true);

        shakyToken.mint(address(this), 1_000_000e18);
        shakyToken.mint(lp, 1_000_000e18);
        stableToken.mint(buyer, 1_000_000e18);

        operator = vm.addr(operatorPk);
        vault.setOperator(operator, true);
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

    /// @dev Full async redeem flow: request → fulfill → claim
    function _redeemAsLP(uint256 shares) internal returns (uint256 assets) {
        vm.startPrank(lp);
        vault.requestRedeem(shares, lp, lp);
        vm.stopPrank();

        vault.fulfillRedeem(lp);

        vm.startPrank(lp);
        assets = vault.redeem(shares, lp, lp);
        vm.stopPrank();
    }

    // ============ DEPOSIT (SYNC, UNCHANGED) ============

    function test_Deposit() public {
        _depositAsLP(100e18);
        assertGt(vault.balanceOf(lp), 0);
        assertEq(vault.totalAssets(), 100e18);
        assertEq(shakyToken.balanceOf(address(vault)), 100e18);
    }

    // ============ ASYNC REDEEM: FULL FLOW ============

    function test_RequestRedeemAndClaim() public {
        _depositAsLP(100e18);
        uint256 shares = vault.balanceOf(lp);
        uint256 halfShares = shares / 2;

        uint256 assets = _redeemAsLP(halfShares);

        assertGt(assets, 0);
        assertApproxEqAbs(assets, 50e18, 1e18);
        assertEq(shakyToken.balanceOf(lp), 1_000_000e18 - 100e18 + assets);
    }

    function test_RequestRedeem_LocksShares() public {
        _depositAsLP(100e18);
        uint256 shares = vault.balanceOf(lp);

        vm.startPrank(lp);
        vault.requestRedeem(shares, lp, lp);
        vm.stopPrank();

        // Shares moved from LP to vault
        assertEq(vault.balanceOf(lp), 0);
        assertEq(vault.balanceOf(address(vault)), shares);

        // Pending shows correct amount
        assertEq(vault.pendingRedeemRequest(0, lp), shares);
        assertEq(vault.claimableRedeemRequest(0, lp), 0);
    }

    function test_FulfillRedeem_SnapshotsPrice() public {
        _depositAsLP(100e18);
        uint256 shares = vault.balanceOf(lp);

        vm.startPrank(lp);
        vault.requestRedeem(shares, lp, lp);
        vm.stopPrank();

        vault.fulfillRedeem(lp);

        // Pending cleared, claimable set
        assertEq(vault.pendingRedeemRequest(0, lp), 0);
        assertEq(vault.claimableRedeemRequest(0, lp), shares);
        assertEq(vault.maxRedeem(lp), shares);
    }

    function test_FulfillRedeem_InsufficientIdle() public {
        _depositAsLP(100e18);
        _mintAndDeliver(80e18); // commit most collateral

        uint256 shares = vault.balanceOf(lp);
        vm.startPrank(lp);
        vault.requestRedeem(shares, lp, lp);
        vm.stopPrank();

        // Not enough idle to fulfill full redemption
        vm.expectRevert(IYieldVault.InsufficientIdle.selector);
        vault.fulfillRedeem(lp);
    }

    function test_PartialClaim() public {
        _depositAsLP(100e18);
        uint256 shares = vault.balanceOf(lp);

        vm.startPrank(lp);
        vault.requestRedeem(shares, lp, lp);
        vm.stopPrank();

        vault.fulfillRedeem(lp);

        // Claim half
        uint256 halfShares = shares / 2;
        vm.startPrank(lp);
        uint256 assets1 = vault.redeem(halfShares, lp, lp);
        vm.stopPrank();

        assertGt(assets1, 0);
        assertEq(vault.claimableRedeemRequest(0, lp), shares - halfShares);

        // Claim the rest
        vm.startPrank(lp);
        uint256 assets2 = vault.redeem(shares - halfShares, lp, lp);
        vm.stopPrank();

        assertGt(assets2, 0);
        assertEq(vault.claimableRedeemRequest(0, lp), 0);
        assertApproxEqAbs(assets1 + assets2, 100e18, 1e18);
    }

    function test_MultipleRequestsAccumulate() public {
        _depositAsLP(100e18);
        uint256 shares = vault.balanceOf(lp);
        uint256 third = shares / 3;

        vm.startPrank(lp);
        vault.requestRedeem(third, lp, lp);
        vault.requestRedeem(third, lp, lp);
        vm.stopPrank();

        assertEq(vault.pendingRedeemRequest(0, lp), third * 2);
    }

    // ============ WITHDRAW DISABLED ============

    function test_WithdrawReverts() public {
        _depositAsLP(100e18);
        vm.startPrank(lp);
        vm.expectRevert(IYieldVault.WithdrawDisabled.selector);
        vault.withdraw(50e18, lp, lp);
        vm.stopPrank();
    }

    function test_MaxWithdrawIsZero() public {
        _depositAsLP(100e18);
        assertEq(vault.maxWithdraw(lp), 0);
    }

    function test_PreviewRedeemReverts() public {
        vm.expectRevert(IYieldVault.AsyncOnly.selector);
        vault.previewRedeem(100e18);
    }

    function test_PreviewWithdrawReverts() public {
        vm.expectRevert(IYieldVault.AsyncOnly.selector);
        vault.previewWithdraw(100e18);
    }

    // ============ OPERATORS ============

    function test_SetOperator() public {
        address operator = address(0x789);

        vm.prank(lp);
        vault.setOperator(operator, true);
        assertTrue(vault.isOperator(lp, operator));

        vm.prank(lp);
        vault.setOperator(operator, false);
        assertFalse(vault.isOperator(lp, operator));
    }

    function test_OperatorCanRequestRedeem() public {
        _depositAsLP(100e18);
        uint256 shares = vault.balanceOf(lp);

        address operator = address(0x789);
        vm.prank(lp);
        vault.setOperator(operator, true);

        // Operator requests on behalf of LP
        vm.prank(operator);
        vault.requestRedeem(shares, lp, lp);

        assertEq(vault.pendingRedeemRequest(0, lp), shares);
    }

    function test_OperatorCanClaimRedeem() public {
        _depositAsLP(100e18);
        uint256 shares = vault.balanceOf(lp);

        vm.startPrank(lp);
        vault.requestRedeem(shares, lp, lp);
        vm.stopPrank();

        vault.fulfillRedeem(lp);

        // Authorize operator to claim
        address operator = address(0x789);
        vm.prank(lp);
        vault.setOperator(operator, true);

        vm.prank(operator);
        uint256 assets = vault.redeem(shares, lp, lp);
        assertGt(assets, 0);
    }

    function test_UnauthorizedRequestReverts() public {
        _depositAsLP(100e18);
        uint256 shares = vault.balanceOf(lp);

        vm.prank(buyer);
        vm.expectRevert(IYieldVault.Unauthorized.selector);
        vault.requestRedeem(shares, buyer, lp);
    }

    function test_UnauthorizedClaimReverts() public {
        _depositAsLP(100e18);
        uint256 shares = vault.balanceOf(lp);

        vm.startPrank(lp);
        vault.requestRedeem(shares, lp, lp);
        vm.stopPrank();

        vault.fulfillRedeem(lp);

        vm.prank(buyer);
        vm.expectRevert(IYieldVault.Unauthorized.selector);
        vault.redeem(shares, buyer, lp);
    }

    function test_SetOperator_CannotApproveSelf() public {
        vm.prank(lp);
        vm.expectRevert(IYieldVault.InvalidAddress.selector);
        vault.setOperator(lp, true);
    }

    // ============ SHARE PRICE NEUTRALITY ============

    function test_SharePriceNeutralDuringPending() public {
        _depositAsLP(100e18);

        // Record price before request
        uint256 priceBefore = vault.convertToAssets(1e18);

        // LP requests redeem for half shares
        uint256 shares = vault.balanceOf(lp);
        vm.startPrank(lp);
        vault.requestRedeem(shares / 2, lp, lp);
        vm.stopPrank();

        // Price should be the same (pending shares still in active supply)
        uint256 priceAfter = vault.convertToAssets(1e18);
        assertEq(priceBefore, priceAfter);
    }

    function test_SharePriceNeutralAfterFulfill() public {
        _depositAsLP(100e18);

        uint256 priceBefore = vault.convertToAssets(1e18);

        uint256 shares = vault.balanceOf(lp);
        vm.startPrank(lp);
        vault.requestRedeem(shares / 2, lp, lp);
        vm.stopPrank();

        vault.fulfillRedeem(lp);

        // Price should still be the same (both shares and assets excluded proportionally)
        uint256 priceAfter = vault.convertToAssets(1e18);
        assertApproxEqAbs(priceBefore, priceAfter, 1);
    }

    // ============ FULFILL BATCH ============

    function test_FulfillRedeems_Batch() public {
        // Two LPs deposit
        address lp2 = address(0x3333);
        shakyToken.mint(lp2, 1_000_000e18);

        _depositAsLP(100e18);

        vm.startPrank(lp2);
        shakyToken.approve(address(vault), 100e18);
        vault.deposit(100e18, lp2);
        vm.stopPrank();

        uint256 lpShares = vault.balanceOf(lp);
        uint256 lp2Shares = vault.balanceOf(lp2);

        // Both request redeem
        vm.prank(lp);
        vault.requestRedeem(lpShares, lp, lp);
        vm.prank(lp2);
        vault.requestRedeem(lp2Shares, lp2, lp2);

        // Batch fulfill
        address[] memory controllers = new address[](2);
        controllers[0] = lp;
        controllers[1] = lp2;
        vault.fulfillRedeems(controllers);

        assertEq(vault.pendingRedeemRequest(0, lp), 0);
        assertEq(vault.pendingRedeemRequest(0, lp2), 0);
        assertGt(vault.claimableRedeemRequest(0, lp), 0);
        assertGt(vault.claimableRedeemRequest(0, lp2), 0);
    }

    // ============ ERC-165 ============

    function test_SupportsInterface() public view {
        assertTrue(vault.supportsInterface(type(IERC7540Redeem).interfaceId));
        assertTrue(vault.supportsInterface(type(IERC7540Operator).interfaceId));
        // ERC-165 itself
        assertTrue(vault.supportsInterface(0x01ffc9a7));
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
        vm.expectRevert(IYieldVault.OnlyHook.selector);
        vault.mintAndDeliver(address(option), 10e18, buyer);
    }

    function test_MintAndDeliver_NotWhitelisted() public {
        _depositAsLP(100e18);
        address opt2 = factory.createOption(
            address(shakyToken), address(stableToken), uint40(block.timestamp + 2 days), 2e18, false
        );
        vm.expectRevert(IYieldVault.NotWhitelisted.selector);
        vault.mintAndDeliver(opt2, 10e18, buyer);
    }

    function test_MintAndDeliver_ExceedsCap() public {
        _depositAsLP(100e18);
        vm.expectRevert(IYieldVault.ExceedsCommitmentCap.selector);
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
        vm.expectRevert(IYieldVault.OnlyHook.selector);
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
        vm.expectRevert(IYieldVault.OnlyHook.selector);
        vault.transferCash(address(stableToken), 1e18, buyer);
    }

    function test_TransferCash_InsufficientCash() public {
        vm.expectRevert(IYieldVault.InsufficientCash.selector);
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

    function test_HandleSettlement_NoOp() public {
        _depositAsLP(100e18);
        _mintAndDeliver(10e18);
        // handleSettlement is now just an event emitter — doesn't revert
        vault.handleSettlement(address(option));
    }

    // ============ ROLLING ============

    function test_RollOptions() public {
        _depositAsLP(100e18);
        _mintAndDeliver(10e18);

        IYieldVault.StrikeConfig[] memory configs = new IYieldVault.StrikeConfig[](2);
        configs[0] = IYieldVault.StrikeConfig({ strikeOffsetBps: 10000, isPut: false, duration: 7 days });
        configs[1] = IYieldVault.StrikeConfig({ strikeOffsetBps: 11000, isPut: false, duration: 7 days });
        vault.setStrategy(configs);
        vault.setRollBounty(0.01e18);

        vm.warp(block.timestamp + 2 days);

        uint256 callerBalBefore = shakyToken.balanceOf(address(this));
        address[] memory newOptions = vault.rollOptions(address(option));

        assertEq(newOptions.length, 2);
        assertTrue(vault.whitelistedOptions(newOptions[0]));
        assertTrue(vault.whitelistedOptions(newOptions[1]));

        assertEq(shakyToken.balanceOf(address(this)) - callerBalBefore, 0.01e18);
    }

    function test_RollOptions_NotExpired() public {
        _depositAsLP(100e18);

        IYieldVault.StrikeConfig[] memory configs = new IYieldVault.StrikeConfig[](1);
        configs[0] = IYieldVault.StrikeConfig({ strikeOffsetBps: 10000, isPut: false, duration: 7 days });
        vault.setStrategy(configs);

        vm.expectRevert(IYieldVault.OptionNotExpired.selector);
        vault.rollOptions(address(option));
    }

    function test_RollOptions_AlreadyRolled() public {
        _depositAsLP(100e18);

        IYieldVault.StrikeConfig[] memory configs = new IYieldVault.StrikeConfig[](1);
        configs[0] = IYieldVault.StrikeConfig({ strikeOffsetBps: 10000, isPut: false, duration: 7 days });
        vault.setStrategy(configs);

        vm.warp(block.timestamp + 2 days);
        vault.rollOptions(address(option));

        vm.expectRevert(IYieldVault.AlreadyRolled.selector);
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

        vm.expectRevert(IYieldVault.InvalidBps.selector);
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
        _depositAsLP(100e18);
        vault.pause();
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
        vault.setSpreadBps(200);
        assertEq(vault.spreadBps(), 200);
    }

    function test_SetSpreadBps_MaxExceeded() public {
        vm.expectRevert(IYieldVault.InvalidBps.selector);
        vault.setSpreadBps(5001);
    }

    function test_SetSpreadBps_OnlyOwner() public {
        vm.prank(lp);
        vm.expectRevert();
        vault.setSpreadBps(100);
    }

    function test_SpreadAffectsQuotes() public {
        (uint256 midBuyOut,) = vault.getQuote(address(option), 100e6, true);
        (uint256 midSellOut,) = vault.getQuote(address(option), 100e18, false);

        vault.setSpreadBps(1000);

        (uint256 spreadBuyOut,) = vault.getQuote(address(option), 100e6, true);
        assertLt(spreadBuyOut, midBuyOut, "Spread should reduce options received when buying");

        (uint256 spreadSellOut,) = vault.getQuote(address(option), 100e18, false);
        assertLt(spreadSellOut, midSellOut, "Spread should reduce cash received when selling");
    }

    function test_ZeroSpreadIsDefault() public {
        assertEq(vault.spreadBps(), 0);
        (uint256 buyOut, uint256 buyPrice) = vault.getQuote(address(option), 100e6, true);
        (uint256 sellOut, uint256 sellPrice) = vault.getQuote(address(option), 100e18, false);
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
        (uint256 flatOut, uint256 flatPrice) = vault.getQuote(address(option), 100e6, true);

        vault.setSkew(-0.2e18);
        vault.setKurtosis(0.1e18);

        (uint256 smileOut, uint256 smilePrice) = vault.getQuote(address(option), 100e6, true);

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

    // ============ BURN ============

    function test_Burn() public {
        _depositAsLP(100e18);
        uint256 delivered = _mintAndDeliver(10e18);

        assertGt(vault.totalCommitted(), 0);

        // Send options back to vault so it can pair-redeem
        vm.prank(buyer);
        IERC20(address(option)).transfer(address(vault), delivered);

        vm.prank(operator);
        vault.burn(address(option), delivered);

        assertEq(vault.committed(address(option)), 0);
        assertEq(vault.totalCommitted(), 0);
        assertEq(IERC20(address(option)).balanceOf(address(vault)), 0);
        assertEq(IERC20(address(redemption)).balanceOf(address(vault)), 0);
    }

    function test_Burn_OnlyOperator() public {
        _depositAsLP(100e18);
        _mintAndDeliver(10e18);

        vm.prank(buyer);
        vm.expectRevert(IYieldVault.Unauthorized.selector);
        vault.burn(address(option), 1e18);
    }

    // ============ EIP-1271: isValidSignature ============

    function test_IsValidSignature_AuthorizedOperator() public view {
        bytes32 testHash = keccak256("test order");
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(operatorPk, testHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        bytes4 result = vault.isValidSignature(testHash, signature);
        assertEq(result, bytes4(0x1626ba7e));
    }

    function test_IsValidSignature_Owner() public {
        // Use a known owner key
        uint256 ownerPk = 0xB0B;
        address ownerAddr = vm.addr(ownerPk);

        // Deploy a new vault with this owner
        vm.prank(ownerAddr);
        YieldVault ownerVault = new YieldVault(
            IERC20(address(shakyToken)),
            "Test",
            "TEST",
            address(factory),
            address(bs),
            address(mockPool),
            address(stableToken),
            1800
        );

        bytes32 testHash = keccak256("test order");
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPk, testHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        bytes4 result = ownerVault.isValidSignature(testHash, signature);
        assertEq(result, bytes4(0x1626ba7e));
    }

    function test_IsValidSignature_Unauthorized() public view {
        bytes32 testHash = keccak256("test order");
        uint256 randoPk = 0xDEAD;
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(randoPk, testHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        bytes4 result = vault.isValidSignature(testHash, signature);
        assertEq(result, bytes4(0xffffffff));
    }

    function test_SupportsInterface_ERC1271() public view {
        assertTrue(vault.supportsInterface(type(IERC1271).interfaceId));
    }

    // ============ ADMIN: BEBOP ============

    function test_SetBebopApprovalTarget() public {
        address target = address(0xBEB0);
        vault.setBebopApprovalTarget(target);
        assertEq(vault.bebopApprovalTarget(), target);
    }

    function test_SetBebopApprovalTarget_OnlyOwner() public {
        vm.prank(lp);
        vm.expectRevert();
        vault.setBebopApprovalTarget(address(0xBEB0));
    }

    // ============ EIP-1271: FULL SETTLEMENT FLOW ============

    function test_EIP1271_FullSettlementFlow() public {
        // --- Setup: auto-mint enabled ---
        MockBebopSettlement settlement = new MockBebopSettlement();
        vault.setBebopApprovalTarget(address(settlement));
        vault.enableAutoMintRedeem(true);
        _depositAsLP(100e18);

        // Approve settlement to pull options from vault (auto-mint creates them during transferFrom)
        uint256 minted = 10e18 - _fee(10e18);
        vm.prank(address(vault));
        IERC20(address(option)).approve(address(settlement), minted);

        // --- MM has USDC ---
        address mm = address(0x4444);
        uint256 cashPayment = 5e18;
        stableToken.mint(mm, cashPayment);
        vm.prank(mm);
        stableToken.approve(address(settlement), cashPayment);

        // --- Step 3: Operator signs the order hash (simulating Bebop's toSign) ---
        bytes32 orderHash = keccak256(
            abi.encode(
                "JamOrder", address(vault), address(option), minted, address(stableToken), cashPayment, block.timestamp + 1 hours
            )
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(operatorPk, orderHash);
        bytes memory operatorSig = abi.encodePacked(r, s, v);

        // --- Step 4: Settlement validates vault's EIP-1271, swaps tokens ---
        uint256 vaultUsdcBefore = stableToken.balanceOf(address(vault));

        // MM calls settlement (in Bebop, the solver/operator broadcasts the tx)
        vm.prank(mm);
        settlement.mockSettle(
            address(vault),           // taker = vault (contract)
            address(option),          // sell token = options
            minted,                   // sell amount
            address(stableToken),     // buy token = USDC
            cashPayment,              // buy amount
            orderHash,
            operatorSig
        );

        // --- Step 5: Verify settlement ---
        // Vault received USDC
        assertEq(stableToken.balanceOf(address(vault)), vaultUsdcBefore + cashPayment);
        // Vault has no options (auto-minted and sent to MM in one step)
        assertEq(IERC20(address(option)).balanceOf(address(vault)), 0);
        // MM received options
        assertEq(IERC20(address(option)).balanceOf(mm), minted);
        // Commitment automatically tracked (live from redemption balances)
        assertGt(vault.committed(address(option)), 0);
        assertGt(vault.totalCommitted(), 0);
        assertEq(vault.committed(address(option)), IERC20(address(redemption)).balanceOf(address(vault)));
    }

    function test_EIP1271_SettlementFailsWithUnauthorizedSigner() public {
        MockBebopSettlement settlement = new MockBebopSettlement();
        vault.setBebopApprovalTarget(address(settlement));
        vault.enableAutoMintRedeem(true);
        _depositAsLP(100e18);

        uint256 optionAmount = 10e18 - _fee(10e18);
        vm.prank(address(vault));
        IERC20(address(option)).approve(address(settlement), optionAmount);

        address mm = address(0x4444);
        stableToken.mint(mm, 5e18);
        vm.prank(mm);
        stableToken.approve(address(settlement), 5e18);

        // Random signer — NOT an authorized operator
        uint256 randoPk = 0xDEAD;
        bytes32 orderHash = keccak256("fake order");
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(randoPk, orderHash);
        bytes memory badSig = abi.encodePacked(r, s, v);

        vm.prank(mm);
        vm.expectRevert("Invalid contract signature");
        settlement.mockSettle(address(vault), address(option), optionAmount, address(stableToken), 5e18, orderHash, badSig);
    }

}
