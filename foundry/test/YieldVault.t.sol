// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

import { Test } from "forge-std/Test.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Factory } from "../contracts/Factory.sol";
import { Receipt as Rct } from "../contracts/Receipt.sol";
import { Option } from "../contracts/Option.sol";
import { YieldVault } from "../contracts/YieldVault.sol";
import { ShakyToken, StableToken } from "../contracts/mocks/ShakyToken.sol";

// ============ Bebop addresses on Base ============
address constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;
address constant JAM_SETTLEMENT = 0xbeb0b0623f66bE8cE162EbDfA2ec543A522F4ea6;
address constant BEBOP_BLEND = 0xbbbbbBB520d69a9775E85b458C58c648259FAD5F;

// ============ Bebop interfaces ============

struct JamOrder {
    address taker;
    address receiver;
    uint256 expiry;
    uint256 exclusivityDeadline;
    uint256 nonce;
    address executor;
    uint256 partnerInfo;
    address[] sellTokens;
    address[] buyTokens;
    uint256[] sellAmounts;
    uint256[] buyAmounts;
    bool usingPermit2;
}

struct BlendSingleOrder {
    uint256 expiry;
    // forge-lint: disable-next-line(mixed-case-variable)
    address taker_address;
    // forge-lint: disable-next-line(mixed-case-variable)
    address maker_address;
    // forge-lint: disable-next-line(mixed-case-variable)
    uint256 maker_nonce;
    // forge-lint: disable-next-line(mixed-case-variable)
    address taker_token;
    // forge-lint: disable-next-line(mixed-case-variable)
    address maker_token;
    // forge-lint: disable-next-line(mixed-case-variable)
    uint256 taker_amount;
    // forge-lint: disable-next-line(mixed-case-variable)
    uint256 maker_amount;
    address receiver;
    // forge-lint: disable-next-line(mixed-case-variable)
    uint256 packed_commands;
    uint256 flags;
}

struct MakerSignature {
    bytes signatureBytes;
    uint256 flags;
}

struct OldSingleQuote {
    bool useOldAmount;
    uint256 makerAmount;
    uint256 makerNonce;
}

interface IJamSettlement {
    function settleInternal(
        JamOrder calldata order,
        bytes calldata signature,
        uint256[] calldata filledAmounts,
        bytes memory hooksData
    ) external payable;
    function settleBebopBlend(address takerAddress, uint8 orderType, bytes memory data, bytes memory hooksData)
        external
        payable;
    function DOMAIN_SEPARATOR() external view returns (bytes32);
    function balanceManager() external view returns (address);
}

interface IBebopBlend {
    function DOMAIN_SEPARATOR() external view returns (bytes32);
    function hashSingleOrder(
        BlendSingleOrder calldata order,
        uint64 partnerId,
        uint256 updatedMakerAmount,
        uint256 updatedMakerNonce
    ) external view returns (bytes32);
}

interface IBebopSettlement {
    function swapSingle(
        BlendSingleOrder calldata order,
        MakerSignature calldata makerSignature,
        uint256 filledTakerAmount
    ) external payable;
    function DOMAIN_SEPARATOR() external view returns (bytes32);
    function hashSingleOrder(
        BlendSingleOrder calldata order,
        uint64 partnerId,
        uint256 updatedMakerAmount,
        uint256 updatedMakerNonce
    ) external view returns (bytes32);
}

interface IPermit2Full {
    function DOMAIN_SEPARATOR() external view returns (bytes32);
    function approve(address token, address spender, uint160 amount, uint48 expiration) external;
}

/// @dev Solver for settleInternal path
contract Solver {
    using SafeERC20 for IERC20;

    function settle(
        address settlement,
        JamOrder calldata order,
        bytes calldata signature,
        uint256[] calldata filledAmounts
    ) external {
        IJamSettlement(settlement).settleInternal(order, signature, filledAmounts, "");
    }

    function approveToken(address token, address spender, uint256 amount) external {
        IERC20(token).forceApprove(spender, amount);
    }
}

contract YieldVaultTest is Test {
    using SafeERC20 for IERC20;

    StableToken public stableToken;
    ShakyToken public shakyToken;
    Factory public factory;
    YieldVault public vault;
    Option public option;
    Rct public redemption;

    address public lp = address(0x1111);
    uint256 public operatorPk = 0xA11CE;
    address public operator;

    // JamOrder EIP-712
    bytes32 constant JAM_ORDER_TYPE_HASH = keccak256(
        "JamOrder(address taker,address receiver,uint256 expiry,uint256 exclusivityDeadline,uint256 nonce,address executor,uint256 partnerInfo,address[] sellTokens,address[] buyTokens,uint256[] sellAmounts,uint256[] buyAmounts,bytes32 hooksHash)"
    );

    // BlendSingleOrder type hash for Permit2 witness (from JAM — includes hooksHash)
    bytes32 constant SINGLE_ORDER_WITNESS_TYPE_HASH = keccak256(
        "SingleOrder(uint64 partner_id,uint256 expiry,address taker_address,address maker_address,uint256 maker_nonce,address taker_token,address maker_token,uint256 taker_amount,uint256 maker_amount,address receiver,uint256 packed_commands,bytes32 hooksHash)"
    );

    // Permit2 witness type for BlendSingleOrder (from JamSettlement)
    string constant BLEND_PERMIT2_ORDER_TYPE =
        "SingleOrder witness)SingleOrder(uint64 partner_id,uint256 expiry,address taker_address,address maker_address,uint256 maker_nonce,address taker_token,address maker_token,uint256 taker_amount,uint256 maker_amount,address receiver,uint256 packed_commands,bytes32 hooksHash)TokenPermissions(address token,uint256 amount)";

    // Permit2 type hashes
    bytes32 constant TOKEN_PERMISSIONS_TYPEHASH = keccak256("TokenPermissions(address token,uint256 amount)");

    function setUp() public {
        vm.createSelectFork(vm.envOr("BASE_RPC_URL", string("https://mainnet.base.org")), 43189435);

        stableToken = new StableToken();
        shakyToken = new ShakyToken();

        Rct redemptionClone = new Rct("Short Option", "SHORT");
        Option optionClone = new Option("Long Option", "LONG");
        factory = new Factory(address(redemptionClone), address(optionClone));

        vault = new YieldVault(IERC20(address(shakyToken)), "Greek Shaky Vault", "gSHAKY", address(factory));
        vault.setupFactoryApproval();
        vault.enableAutoMintRedeem(true);

        address optionAddr = factory.createOption(
            address(shakyToken), address(stableToken), uint40(block.timestamp + 1 days), 1e18, false
        );
        option = Option(optionAddr);
        redemption = option.receipt();
        vault.addOption(address(option), address(0));

        shakyToken.mint(address(this), 1_000_000e18);
        shakyToken.mint(lp, 1_000_000e18);

        operator = vm.addr(operatorPk);
        vault.setOperator(operator, true);
    }

    function _fee(uint256) internal pure returns (uint256) {
        return 0;
    }

    function _depositAsLp(uint256 amount) internal {
        vm.startPrank(lp);
        shakyToken.approve(address(vault), amount);
        vault.deposit(amount, lp);
        vm.stopPrank();
    }

    // ============ DEPOSIT ============

    function test_Deposit() public {
        _depositAsLp(100e18);
        assertGt(vault.balanceOf(lp), 0);
        assertEq(vault.totalAssets(), 100e18);
    }

    // ============ ASYNC REDEEM ============

    function test_RequestRedeemAndClaim() public {
        _depositAsLp(100e18);
        uint256 shares = vault.balanceOf(lp);

        vm.prank(lp);
        vault.requestRedeem(shares / 2, lp, lp);
        vault.fulfillRedeem(lp);

        vm.prank(lp);
        uint256 assets = vault.redeem(shares / 2, lp, lp);
        assertApproxEqAbs(assets, 50e18, 1e18);
    }

    function test_PartialClaim() public {
        _depositAsLp(100e18);
        uint256 shares = vault.balanceOf(lp);

        vm.prank(lp);
        vault.requestRedeem(shares, lp, lp);
        vault.fulfillRedeem(lp);

        vm.prank(lp);
        uint256 a1 = vault.redeem(shares / 2, lp, lp);
        vm.prank(lp);
        uint256 a2 = vault.redeem(shares - shares / 2, lp, lp);
        assertApproxEqAbs(a1 + a2, 100e18, 1e18);
    }

    function test_WithdrawReverts() public {
        _depositAsLp(100e18);
        vm.prank(lp);
        vm.expectRevert(YieldVault.WithdrawDisabled.selector);
        vault.withdraw(50e18, lp, lp);
    }

    function test_SharePriceNeutralAfterFulfill() public {
        _depositAsLp(100e18);
        uint256 priceBefore = vault.convertToAssets(1e18);
        uint256 halfShares = vault.balanceOf(lp) / 2;

        vm.prank(lp);
        vault.requestRedeem(halfShares, lp, lp);
        vault.fulfillRedeem(lp);

        assertApproxEqAbs(priceBefore, vault.convertToAssets(1e18), 1);
    }

    // ============ OPERATORS ============

    function test_SetOperator() public {
        vm.prank(lp);
        vault.setOperator(address(0x789), true);
        assertTrue(vault.isOperator(lp, address(0x789)));
    }

    function test_UnauthorizedClaimReverts() public {
        _depositAsLp(100e18);
        uint256 shares = vault.balanceOf(lp);
        vm.prank(lp);
        vault.requestRedeem(shares, lp, lp);
        vault.fulfillRedeem(lp);

        vm.prank(address(0xDEAD));
        vm.expectRevert(YieldVault.Unauthorized.selector);
        vault.redeem(shares, address(0xDEAD), lp);
    }

    // ============ EIP-1271 ============

    function test_IsValidSignature() public view {
        bytes32 h = keccak256("test");
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(operatorPk, h);
        assertEq(vault.isValidSignature(h, abi.encodePacked(r, s, v)), bytes4(0x1626ba7e));
    }

    function test_IsValidSignature_Unauthorized() public view {
        bytes32 h = keccak256("test");
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(0xDEAD, h);
        assertEq(vault.isValidSignature(h, abi.encodePacked(r, s, v)), bytes4(0xffffffff));
    }

    // ============ BEBOP JAM: settleInternal on real fork ============

    function test_BebopJam_SettleInternal() public {
        _depositAsLp(100e18);

        // Solver holds USDC (acts as counterparty)
        Solver solver = new Solver();
        uint256 cashPayment = 5e18;
        stableToken.mint(address(solver), cashPayment);
        address balMgr = IJamSettlement(JAM_SETTLEMENT).balanceManager();
        solver.approveToken(address(stableToken), balMgr, cashPayment);

        // Vault approves BalanceManager to pull options (auto-mint creates them)
        uint256 optionAmount = 10e18 - _fee(10e18);
        vm.prank(address(vault));
        IERC20(address(option)).approve(balMgr, optionAmount);

        // Build JamOrder
        address[] memory sellTokens = new address[](1);
        sellTokens[0] = address(option);
        address[] memory buyTokens = new address[](1);
        buyTokens[0] = address(stableToken);
        uint256[] memory sellAmounts = new uint256[](1);
        sellAmounts[0] = optionAmount;
        uint256[] memory buyAmounts = new uint256[](1);
        buyAmounts[0] = cashPayment;

        JamOrder memory order = JamOrder({
            taker: address(vault),
            receiver: address(vault),
            expiry: block.timestamp + 1 hours,
            exclusivityDeadline: 0,
            nonce: 1,
            executor: address(solver),
            partnerInfo: 0,
            sellTokens: sellTokens,
            buyTokens: buyTokens,
            sellAmounts: sellAmounts,
            buyAmounts: buyAmounts,
            usingPermit2: false
        });

        // Operator signs the EIP-712 digest
        bytes32 orderHash = keccak256(
            abi.encode(
                JAM_ORDER_TYPE_HASH,
                order.taker,
                order.receiver,
                order.expiry,
                order.exclusivityDeadline,
                order.nonce,
                order.executor,
                order.partnerInfo,
                keccak256(abi.encodePacked(order.sellTokens)),
                keccak256(abi.encodePacked(order.buyTokens)),
                keccak256(abi.encodePacked(order.sellAmounts)),
                keccak256(abi.encodePacked(order.buyAmounts)),
                bytes32(0) // empty hooks hash
            )
        );
        bytes32 digest =
            keccak256(abi.encodePacked("\x19\x01", IJamSettlement(JAM_SETTLEMENT).DOMAIN_SEPARATOR(), orderHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(operatorPk, digest);

        uint256[] memory filledAmounts = new uint256[](1);
        filledAmounts[0] = cashPayment;

        solver.settle(JAM_SETTLEMENT, order, abi.encodePacked(r, s, v), filledAmounts);

        // Vault received USDC
        assertEq(stableToken.balanceOf(address(vault)), cashPayment);
        // Options auto-minted and sent to solver
        assertEq(IERC20(address(option)).balanceOf(address(solver)), optionAmount);
        // Commitment tracked
        assertGt(vault.committed(address(option)), 0);
    }

    function test_BebopJam_RejectsUnauthorizedSigner() public {
        _depositAsLp(100e18);

        Solver solver = new Solver();
        stableToken.mint(address(solver), 5e18);
        address balMgr = IJamSettlement(JAM_SETTLEMENT).balanceManager();
        solver.approveToken(address(stableToken), balMgr, 5e18);

        uint256 optionAmount = 10e18 - _fee(10e18);
        vm.prank(address(vault));
        IERC20(address(option)).approve(balMgr, optionAmount);

        address[] memory sellTokens = new address[](1);
        sellTokens[0] = address(option);
        address[] memory buyTokens = new address[](1);
        buyTokens[0] = address(stableToken);
        uint256[] memory sellAmounts = new uint256[](1);
        sellAmounts[0] = optionAmount;
        uint256[] memory buyAmounts = new uint256[](1);
        buyAmounts[0] = 5e18;

        JamOrder memory order = JamOrder({
            taker: address(vault),
            receiver: address(vault),
            expiry: block.timestamp + 1 hours,
            exclusivityDeadline: 0,
            nonce: 1,
            executor: address(solver),
            partnerInfo: 0,
            sellTokens: sellTokens,
            buyTokens: buyTokens,
            sellAmounts: sellAmounts,
            buyAmounts: buyAmounts,
            usingPermit2: false
        });

        // Sign with unauthorized key
        bytes32 orderHash = keccak256(
            abi.encode(
                JAM_ORDER_TYPE_HASH,
                order.taker,
                order.receiver,
                order.expiry,
                order.exclusivityDeadline,
                order.nonce,
                order.executor,
                order.partnerInfo,
                keccak256(abi.encodePacked(order.sellTokens)),
                keccak256(abi.encodePacked(order.buyTokens)),
                keccak256(abi.encodePacked(order.sellAmounts)),
                keccak256(abi.encodePacked(order.buyAmounts)),
                bytes32(0)
            )
        );
        bytes32 digest =
            keccak256(abi.encodePacked("\x19\x01", IJamSettlement(JAM_SETTLEMENT).DOMAIN_SEPARATOR(), orderHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(0xDEAD, digest);

        uint256[] memory filledAmounts = new uint256[](1);
        filledAmounts[0] = 5e18;

        vm.expectRevert();
        solver.settle(JAM_SETTLEMENT, order, abi.encodePacked(r, s, v), filledAmounts);
    }

    // ============ BEBOP BLEND: settleBebopBlend on real fork ============

    function test_BebopBlend_SettleSingle() public {
        _depositAsLp(100e18);

        uint256 makerPk = 0xB0B;
        address maker = vm.addr(makerPk);
        uint256 optionAmount = 10e18 - _fee(10e18);
        uint256 cashPayment = 5e18;

        // Fund maker with USDC and approve BebopBlend
        stableToken.mint(maker, cashPayment);
        vm.prank(maker);
        stableToken.approve(BEBOP_BLEND, cashPayment);

        // Vault approves Permit2 for options (Permit2 pulls during settlement)
        vm.prank(address(vault));
        IERC20(address(option)).approve(PERMIT2, optionAmount);

        // Build BlendSingleOrder
        // taker_address = JamSettlement (proxy), real taker = vault
        // packed_commands: 0 = no native tokens, no permit2 for taker transfer (JamSettlement handles it)
        uint256 permit2Nonce = 0;
        BlendSingleOrder memory blendOrder = BlendSingleOrder({
            expiry: block.timestamp + 1 hours,
            taker_address: JAM_SETTLEMENT, // JamSettlement acts as taker on BebopBlend
            maker_address: address(0), // will be overwritten by settleBebopBlend
            maker_nonce: 1,
            taker_token: address(option),
            maker_token: address(stableToken),
            taker_amount: optionAmount,
            maker_amount: cashPayment,
            receiver: address(vault), // vault receives maker's USDC
            packed_commands: 0,
            flags: (permit2Nonce << 128) // upper 128 bits = permit2 nonce / event id
        });

        // Maker signs the BebopBlend order (with their address filled in — BebopBlend validates this)
        BlendSingleOrder memory makerOrder = blendOrder;
        makerOrder.maker_address = maker;
        bytes32 makerDigest = IBebopBlend(BEBOP_BLEND).hashSingleOrder(makerOrder, 0, 0, 0);
        (uint8 mv, bytes32 mr, bytes32 ms) = vm.sign(makerPk, makerDigest);
        MakerSignature memory makerSig = MakerSignature({
            signatureBytes: abi.encodePacked(mr, ms, mv),
            flags: 0 // EIP-712, no Permit2 for maker
        });

        // Taker (vault) signs via Permit2 witness
        // The witness is the BlendSingleOrder hash used by JamBalanceManager
        OldSingleQuote memory takerQuoteInfo = OldSingleQuote({
            useOldAmount: false, makerAmount: blendOrder.maker_amount, makerNonce: blendOrder.maker_nonce
        });

        // Compute the Permit2 witness (BlendSingleOrder hash from JAM's perspective)
        bytes32 blendOrderWitness = keccak256(
            abi.encode(
                SINGLE_ORDER_WITNESS_TYPE_HASH,
                uint64(blendOrder.flags >> 64), // partnerId
                blendOrder.expiry,
                blendOrder.taker_address,
                blendOrder.maker_address,
                takerQuoteInfo.makerNonce,
                blendOrder.taker_token,
                blendOrder.maker_token,
                blendOrder.taker_amount,
                takerQuoteInfo.makerAmount,
                blendOrder.receiver,
                blendOrder.packed_commands,
                bytes32(0) // hooksHash
            )
        );

        // Compute Permit2 digest (single transfer, not batch)
        bytes32 permit2TypeHash = keccak256(
            abi.encodePacked(
                "PermitWitnessTransferFrom(TokenPermissions permitted,address spender,uint256 nonce,uint256 deadline,",
                BLEND_PERMIT2_ORDER_TYPE
            )
        );
        bytes32 tokenPermHash = keccak256(
            abi.encode(TOKEN_PERMISSIONS_TYPEHASH, address(blendOrder.taker_token), blendOrder.taker_amount)
        );
        address balMgr = IJamSettlement(JAM_SETTLEMENT).balanceManager();
        bytes32 permit2Struct = keccak256(
            abi.encode(
                permit2TypeHash,
                tokenPermHash,
                balMgr, // spender = BalanceManager
                blendOrder.flags >> 128, // nonce
                blendOrder.expiry, // deadline
                blendOrderWitness
            )
        );
        bytes32 permit2Digest =
            keccak256(abi.encodePacked("\x19\x01", IPermit2Full(PERMIT2).DOMAIN_SEPARATOR(), permit2Struct));
        (uint8 tv, bytes32 tr, bytes32 ts) = vm.sign(operatorPk, permit2Digest);
        bytes memory takerSignature = abi.encodePacked(tr, ts, tv);

        // Encode data for settleBebopBlend
        bytes memory data = abi.encode(
            blendOrder,
            makerSig,
            takerQuoteInfo,
            maker, // makerAddress (overwritten into order)
            uint256(0), // newFlags
            takerSignature
        );

        // Execute through real JamSettlement → BebopBlend
        IJamSettlement(JAM_SETTLEMENT)
            .settleBebopBlend(
                address(vault), // takerAddress = vault
                0, // orderType = Single
                data,
                "" // no hooks
            );

        // Verify
        assertEq(stableToken.balanceOf(address(vault)), cashPayment, "Vault should receive USDC");
        assertEq(IERC20(address(option)).balanceOf(address(vault)), 0, "Vault options should be pulled");
        assertGt(vault.committed(address(option)), 0, "Commitment should be tracked");
    }

    // ============ BEBOP RFQ-T: swapSingle via vault.execute (no taker signature) ============

    function test_BebopSwapSingle_OperatorSubmits() public {
        _depositAsLp(100e18);

        // MM signs a quote to sell USDC for options
        uint256 makerPk = 0xB0B;
        address maker = vm.addr(makerPk);
        uint256 optionAmount = 10e18 - _fee(10e18);
        uint256 cashPayment = 5e18;

        // Fund MM and approve BebopSettlement
        stableToken.mint(maker, cashPayment);
        vm.prank(maker);
        stableToken.approve(BEBOP_BLEND, cashPayment);

        // Owner pre-approves BebopSettlement to pull option tokens from vault
        vault.approveToken(address(option), BEBOP_BLEND, optionAmount);

        // Build order: vault is taker (sells options), MM is maker (sells USDC)
        BlendSingleOrder memory order = BlendSingleOrder({
            expiry: block.timestamp + 1 hours,
            taker_address: address(vault),
            maker_address: maker,
            maker_nonce: 1,
            taker_token: address(option),
            maker_token: address(stableToken),
            taker_amount: optionAmount,
            maker_amount: cashPayment,
            receiver: address(vault),
            packed_commands: 0,
            flags: 0
        });

        // MM signs the order — only signature needed
        bytes32 makerDigest = IBebopSettlement(BEBOP_BLEND).hashSingleOrder(order, 0, 0, 0);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(makerPk, makerDigest);
        MakerSignature memory makerSig = MakerSignature({ signatureBytes: abi.encodePacked(r, s, v), flags: 0 });

        // Operator submits via vault.execute — vault is msg.sender so swapSingle accepts it
        vm.prank(operator);
        vault.execute(BEBOP_BLEND, abi.encodeCall(IBebopSettlement.swapSingle, (order, makerSig, 0)));

        // Verify
        assertEq(stableToken.balanceOf(address(vault)), cashPayment, "Vault should receive USDC");
        assertGt(vault.committed(address(option)), 0, "Commitment should be tracked");
    }

    // ============ BURN ============

    function test_Burn() public {
        _depositAsLp(100e18);
        option.mint(address(vault), 10e18);
        assertGt(vault.committed(address(option)), 0);

        vm.prank(operator);
        vault.burn(address(option), 10e18 - _fee(10e18));
        assertEq(vault.committed(address(option)), 0);
    }

    function test_Burn_OnlyOperator() public {
        vm.prank(address(0xDEAD));
        vm.expectRevert(YieldVault.Unauthorized.selector);
        vault.burn(address(option), 1e18);
    }

    // ============ ADMIN ============

    function test_AddOption() public {
        address opt2 = factory.createOption(
            address(shakyToken), address(stableToken), uint40(block.timestamp + 2 days), 2e18, false
        );
        vault.addOption(opt2, address(0));
        assertEq(vault.activeOptions(1), opt2);
    }

    function test_Pause() public {
        _depositAsLp(100e18);
        vault.pause();
        assertEq(vault.maxDeposit(lp), 0);
    }

    function test_GetVaultStats() public {
        _depositAsLp(100e18);
        (uint256 totalAssets_,, uint256 idle_,,) = vault.getVaultStats();
        assertEq(totalAssets_, 100e18);
        assertEq(idle_, 100e18);
    }

    // ============ REDEEM EXPIRED ============

    function test_RedeemExpired() public {
        _depositAsLp(100e18);
        option.mint(address(vault), 10e18);
        assertGt(vault.committed(address(option)), 0);

        vm.warp(block.timestamp + 2 days);
        vault.redeemExpired(address(option));
        assertEq(vault.committed(address(option)), 0);
    }

    // ============ END-TO-END DEMO ============

    function test_Demo_DepositSellOptionsExpireWithdrawProfit() public {
        // 1. LP deposits 100 collateral
        _depositAsLp(100e18);
        uint256 shares = vault.balanceOf(lp);
        uint256 assetsBefore = vault.totalAssets();

        // 2. Mint options from vault collateral (simulates auto-mint during Bebop settlement)
        option.mint(address(vault), 10e18);
        uint256 optionAmount = 10e18 - _fee(10e18);

        // 3. Simulate selling options: options leave vault, premium arrives in collateral token
        vm.prank(address(vault));
        // forge-lint: disable-next-line(erc20-unchecked-transfer)
        IERC20(address(option)).transfer(address(0xBEEF), optionAmount);
        uint256 premium = 0.5e18;
        shakyToken.mint(address(vault), premium);

        // totalAssets reflects premium (premium in collateral token adds to idle balance)
        assertGt(vault.totalAssets(), assetsBefore);

        // 4. Options expire OTM (no exercise)
        vm.warp(block.timestamp + 2 days);

        // 5. Vault recovers collateral from expired Collateral tokens
        vault.redeemExpired(address(option));
        assertEq(vault.committed(address(option)), 0);

        // 6. LP redeems all shares via async flow
        vm.prank(lp);
        vault.requestRedeem(shares, lp, lp);
        vault.fulfillRedeem(lp);
        vm.prank(lp);
        uint256 assetsOut = vault.redeem(shares, lp, lp);

        // 7. LP got more than deposited (premium minus mint fees)
        assertGt(assetsOut, 100e18, "LP should profit from premium");
    }
}
