// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

import { Test } from "forge-std/Test.sol";
import { IERC20, ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { OptionFactory, Redemption, Option } from "../contracts/OptionFactory.sol";
import { YieldVault } from "../contracts/YieldVault.sol";
import { IYieldVault } from "../contracts/interfaces/IYieldVault.sol";
import { IERC7540Redeem, IERC7540Operator } from "../contracts/interfaces/IERC7540.sol";
import { IERC1271 } from "@openzeppelin/contracts/interfaces/IERC1271.sol";
import { ShakyToken, StableToken } from "../contracts/ShakyToken.sol";

/// @dev Simulates Bebop's settlement: validates EIP-1271 signature, pulls options from taker, sends USDC
contract MockBebopSettlement {
    using SafeERC20 for IERC20;

    function mockSettle(
        address taker,
        address sellToken,
        uint256 sellAmount,
        address buyToken,
        uint256 buyAmount,
        bytes32 orderHash,
        bytes calldata signature
    ) external {
        if (taker.code.length > 0) {
            bytes4 magic = IERC1271(taker).isValidSignature(orderHash, signature);
            require(magic == 0x1626ba7e, "Invalid contract signature");
        }
        IERC20(sellToken).safeTransferFrom(taker, msg.sender, sellAmount);
        IERC20(buyToken).safeTransferFrom(msg.sender, taker, buyAmount);
    }
}

contract YieldVaultTest is Test {
    using SafeERC20 for IERC20;

    StableToken public stableToken;
    ShakyToken public shakyToken;
    OptionFactory public factory;
    YieldVault public vault;
    Option public option;
    Redemption public redemption;

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

        vault = new YieldVault(IERC20(address(shakyToken)), "Greek Shaky Vault", "gSHAKY", address(factory));

        vault.setupFactoryApproval();

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

    // ============ DEPOSIT ============

    function test_Deposit() public {
        _depositAsLP(100e18);
        assertGt(vault.balanceOf(lp), 0);
        assertEq(vault.totalAssets(), 100e18);
        assertEq(shakyToken.balanceOf(address(vault)), 100e18);
    }

    // ============ ASYNC REDEEM ============

    function test_RequestRedeemAndClaim() public {
        _depositAsLP(100e18);
        uint256 shares = vault.balanceOf(lp);
        uint256 halfShares = shares / 2;

        vm.prank(lp);
        vault.requestRedeem(halfShares, lp, lp);
        vault.fulfillRedeem(lp);

        vm.prank(lp);
        uint256 assets = vault.redeem(halfShares, lp, lp);

        assertGt(assets, 0);
        assertApproxEqAbs(assets, 50e18, 1e18);
    }

    function test_RequestRedeem_LocksShares() public {
        _depositAsLP(100e18);
        uint256 shares = vault.balanceOf(lp);

        vm.prank(lp);
        vault.requestRedeem(shares, lp, lp);

        assertEq(vault.balanceOf(lp), 0);
        assertEq(vault.balanceOf(address(vault)), shares);
        assertEq(vault.pendingRedeemRequest(0, lp), shares);
    }

    function test_FulfillRedeem_SnapshotsPrice() public {
        _depositAsLP(100e18);
        uint256 shares = vault.balanceOf(lp);

        vm.prank(lp);
        vault.requestRedeem(shares, lp, lp);
        vault.fulfillRedeem(lp);

        assertEq(vault.pendingRedeemRequest(0, lp), 0);
        assertEq(vault.claimableRedeemRequest(0, lp), shares);
        assertEq(vault.maxRedeem(lp), shares);
    }

    function test_PartialClaim() public {
        _depositAsLP(100e18);
        uint256 shares = vault.balanceOf(lp);

        vm.prank(lp);
        vault.requestRedeem(shares, lp, lp);
        vault.fulfillRedeem(lp);

        uint256 halfShares = shares / 2;
        vm.prank(lp);
        uint256 assets1 = vault.redeem(halfShares, lp, lp);

        vm.prank(lp);
        uint256 assets2 = vault.redeem(shares - halfShares, lp, lp);

        assertApproxEqAbs(assets1 + assets2, 100e18, 1e18);
    }

    function test_WithdrawReverts() public {
        _depositAsLP(100e18);
        vm.prank(lp);
        vm.expectRevert(IYieldVault.WithdrawDisabled.selector);
        vault.withdraw(50e18, lp, lp);
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

    function test_SharePriceNeutralDuringPending() public {
        _depositAsLP(100e18);
        uint256 priceBefore = vault.convertToAssets(1e18);

        uint256 shares = vault.balanceOf(lp);
        vm.prank(lp);
        vault.requestRedeem(shares / 2, lp, lp);

        assertEq(priceBefore, vault.convertToAssets(1e18));
    }

    function test_SharePriceNeutralAfterFulfill() public {
        _depositAsLP(100e18);
        uint256 priceBefore = vault.convertToAssets(1e18);

        uint256 shares = vault.balanceOf(lp);
        vm.prank(lp);
        vault.requestRedeem(shares / 2, lp, lp);
        vault.fulfillRedeem(lp);

        assertApproxEqAbs(priceBefore, vault.convertToAssets(1e18), 1);
    }

    // ============ OPERATORS ============

    function test_SetOperator() public {
        address op = address(0x789);
        vm.prank(lp);
        vault.setOperator(op, true);
        assertTrue(vault.isOperator(lp, op));

        vm.prank(lp);
        vault.setOperator(op, false);
        assertFalse(vault.isOperator(lp, op));
    }

    function test_OperatorCanRequestRedeem() public {
        _depositAsLP(100e18);
        uint256 shares = vault.balanceOf(lp);

        vm.prank(lp);
        vault.setOperator(operator, true);

        vm.prank(operator);
        vault.requestRedeem(shares, lp, lp);
        assertEq(vault.pendingRedeemRequest(0, lp), shares);
    }

    function test_UnauthorizedRequestReverts() public {
        _depositAsLP(100e18);
        uint256 shares = vault.balanceOf(lp);
        vm.prank(buyer);
        vm.expectRevert();
        vault.requestRedeem(shares, buyer, lp);
    }

    function test_UnauthorizedClaimReverts() public {
        _depositAsLP(100e18);
        uint256 shares = vault.balanceOf(lp);
        vm.prank(lp);
        vault.requestRedeem(shares, lp, lp);
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

    // ============ BURN ============

    function test_Burn() public {
        _depositAsLP(100e18);

        // Mint options to vault via auto-mint (transfer triggers it)
        vault.enableAutoMintRedeem(true);
        uint256 optionAmount = 10e18 - _fee(10e18);

        // Mint options directly for the vault to hold
        option.mint(address(vault), 10e18);

        assertGt(vault.committed(address(option)), 0);

        vm.prank(operator);
        vault.burn(address(option), optionAmount);

        assertEq(vault.committed(address(option)), 0);
        assertEq(vault.totalCommitted(), 0);
    }

    function test_Burn_OnlyOperator() public {
        vm.prank(buyer);
        vm.expectRevert(IYieldVault.Unauthorized.selector);
        vault.burn(address(option), 1e18);
    }

    // ============ EIP-1271 ============

    function test_IsValidSignature_AuthorizedOperator() public view {
        bytes32 testHash = keccak256("test order");
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(operatorPk, testHash);

        bytes4 result = vault.isValidSignature(testHash, abi.encodePacked(r, s, v));
        assertEq(result, bytes4(0x1626ba7e));
    }

    function test_IsValidSignature_Unauthorized() public view {
        bytes32 testHash = keccak256("test order");
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(0xDEAD, testHash);

        bytes4 result = vault.isValidSignature(testHash, abi.encodePacked(r, s, v));
        assertEq(result, bytes4(0xffffffff));
    }

    function test_SupportsInterface() public view {
        assertTrue(vault.supportsInterface(type(IERC7540Redeem).interfaceId));
        assertTrue(vault.supportsInterface(type(IERC7540Operator).interfaceId));
        assertTrue(vault.supportsInterface(type(IERC1271).interfaceId));
        assertTrue(vault.supportsInterface(0x01ffc9a7)); // ERC-165
    }

    // ============ EIP-1271: FULL SETTLEMENT FLOW ============

    function test_EIP1271_FullSettlementFlow() public {
        MockBebopSettlement settlement = new MockBebopSettlement();
        vault.setBebopApprovalTarget(address(settlement));
        vault.enableAutoMintRedeem(true);
        _depositAsLP(100e18);

        uint256 optionAmount = 10e18 - _fee(10e18);
        vm.prank(address(vault));
        IERC20(address(option)).approve(address(settlement), optionAmount);

        // MM has USDC
        address mm = address(0x4444);
        uint256 cashPayment = 5e18;
        stableToken.mint(mm, cashPayment);
        vm.prank(mm);
        stableToken.approve(address(settlement), cashPayment);

        // Operator signs order hash
        bytes32 orderHash = keccak256(abi.encode("JamOrder", address(vault), address(option), optionAmount));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(operatorPk, orderHash);

        // Settle: options auto-minted from vault → MM, USDC from MM → vault
        vm.prank(mm);
        settlement.mockSettle(
            address(vault), address(option), optionAmount, address(stableToken), cashPayment, orderHash, abi.encodePacked(r, s, v)
        );

        // Vault received USDC
        assertEq(stableToken.balanceOf(address(vault)), cashPayment);
        // Vault has no options (auto-minted and sent to MM)
        assertEq(IERC20(address(option)).balanceOf(address(vault)), 0);
        // MM received options
        assertEq(IERC20(address(option)).balanceOf(mm), optionAmount);
        // Commitment tracked (live from redemption balances)
        assertGt(vault.committed(address(option)), 0);
        assertGt(vault.totalCommitted(), 0);
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

        // Random signer — NOT authorized
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(0xDEAD, keccak256("fake"));

        vm.prank(mm);
        vm.expectRevert("Invalid contract signature");
        settlement.mockSettle(
            address(vault), address(option), optionAmount, address(stableToken), 5e18, keccak256("fake"), abi.encodePacked(r, s, v)
        );
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

    function test_SetBebopApprovalTarget() public {
        vault.setBebopApprovalTarget(address(0xBEB0));
        assertEq(vault.bebopApprovalTarget(), address(0xBEB0));
    }

    function test_Pause() public {
        _depositAsLP(100e18);
        vault.pause();
        assertEq(vault.maxDeposit(lp), 0);
    }

    // ============ VIEW ============

    function test_GetVaultStats() public {
        _depositAsLP(100e18);
        (uint256 totalAssets_, uint256 totalShares_, uint256 idle_, uint256 committed_, uint256 utilBps_) =
            vault.getVaultStats();

        assertEq(totalAssets_, 100e18);
        assertGt(totalShares_, 0);
        assertEq(idle_, 100e18);
        assertEq(committed_, 0);
        assertEq(utilBps_, 0);
    }

    function test_UtilizationBps() public {
        _depositAsLP(100e18);
        assertEq(vault.utilizationBps(), 0);
    }
}
