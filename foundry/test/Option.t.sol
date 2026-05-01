// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { Test } from "forge-std/Test.sol";
import { IERC20, ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Factory } from "../contracts/Factory.sol";
import { Receipt as Rct } from "../contracts/Receipt.sol";
import { Option } from "../contracts/Option.sol";
import { CreateParams } from "../contracts/interfaces/IFactory.sol";
import { Balances, OptionInfo, TokenData } from "../contracts/interfaces/IOption.sol";
import { ShakyToken, StableToken } from "../contracts/mocks/ShakyToken.sol";

contract OptionTest is Test {
    using SafeERC20 for IERC20;

    StableToken public stableToken;
    ShakyToken public shakyToken;
    Rct public redemptionClone;
    Option public optionClone;
    Factory public factory;

    Option option;
    Rct redemption;
    address shakyTokenAddr;
    address stableTokenAddr;
    address factoryAddr;

    uint160 constant MAX160 = type(uint160).max;
    uint48 constant MAX48 = type(uint48).max;
    uint256 constant MAX256 = type(uint256).max;

    function setUp() public {
        // Fork Base
        vm.createSelectFork(vm.envOr("BASE_RPC_URL", string("https://mainnet.base.org")), 43189435);

        // Deploy tokens
        stableToken = new StableToken();
        shakyToken = new ShakyToken();
        shakyTokenAddr = address(shakyToken);
        stableTokenAddr = address(stableToken);

        // Mint tokens to test address
        stableToken.mint(address(this), 1_000_000 * 10 ** 18);
        shakyToken.mint(address(this), 1_000_000 * 10 ** 18);

        // Deploy Collateral template
        redemptionClone = new Rct("Short Option", "SHORT");

        // Deploy Option template
        optionClone = new Option("Long Option", "LONG");

        // Deploy Factory
        factory = new Factory(address(redemptionClone), address(optionClone));
        factoryAddr = address(factory);

        CreateParams[] memory options = new CreateParams[](1);
        options[0] = CreateParams({
            collateral: address(shakyToken),
            consideration: address(stableToken),
            expirationDate: uint40(block.timestamp + 1 days),
            strike: 1e18,
            isPut: false,
            isEuro: false,
            windowSeconds: 0
        });

        address optionAddress = factory.createOption(options[0]);
        option = Option(optionAddress);

        redemption = Rct(option.receipt());

        approve1(shakyTokenAddr);
        approve1(stableTokenAddr);
    }

    function approve1(address token) public {
        IERC20(token).approve(factoryAddr, MAX256);
        factory.approve(token, MAX160);
    }

    function safeTransfer(address token, address to, uint256 amount) internal {
        IERC20(token).safeTransfer(to, amount);
    }

    function safeTransferFrom(address token, address from, address to, uint256 amount) internal {
        IERC20(token).safeTransferFrom(from, to, amount);
    }

    function test_Mint() public {
        uint256 collBefore = shakyToken.balanceOf(address(this));
        uint256 mintAmount = 1e18;
        option.mint(mintAmount);
        uint256 collAfter = shakyToken.balanceOf(address(this));

        // Collateral deposited
        assertEq(collBefore - collAfter, mintAmount);
        // Collateral minted 1:1 (no fees)
        assertEq(redemption.balanceOf(address(this)), mintAmount);
        // Option minted 1:1 (no fees)
        assertEq(option.balanceOf(address(this)), mintAmount);
        // Collateral held by redemption contract
        assertEq(shakyToken.balanceOf(address(redemption)), mintAmount);
    }

    function test_Transfer1() public {
        factory.enableAutoMintBurn(true);
        uint256 collBefore = shakyToken.balanceOf(address(this));
        // Transfer without minting first — triggers auto-mint (requires opt-in)
        safeTransfer(address(option), address(0x123), 5);

        // Auto-mint deposited collateral
        assertGt(collBefore - shakyToken.balanceOf(address(this)), 0);
        // Recipient got option tokens
        assertEq(option.balanceOf(address(0x123)), 5);
        // Sender got redemption tokens from auto-mint (fee-adjusted: mints slightly more to cover fee)
        assertGe(redemption.balanceOf(address(this)), 5);
        // Sender may have dust option tokens from ceiling rounding
        assertLe(option.balanceOf(address(this)), 1);
    }

    function test_TransferTransfer() public {
        factory.enableAutoMintBurn(true); // opt-in for auto-redeem on receive
        option.mint(10);
        uint256 balance = option.balanceOf(address(this));

        safeTransfer(address(option), address(0x123), 5);
        // 0x123 has no redemptions, so no auto-redeem
        assertEq(option.balanceOf(address(0x123)), 5);

        vm.prank(address(0x123));
        safeTransfer(address(option), address(this), 3);
        // Sender (this) has redemption tokens and opted in, so auto-redeem fires
        // 3 option+redemption pairs burned, collateral returned
        assertEq(option.balanceOf(address(0x123)), 2);
        assertEq(option.balanceOf(address(this)), balance - 5); // original minus transferred
        assertEq(redemption.balanceOf(address(this)), balance - 3); // 3 auto-redeemed
    }

    function test_Exercise1() public {
        option.mint(1e18);
        uint256 optBalance = option.balanceOf(address(this));

        uint256 collBefore = shakyToken.balanceOf(address(this));
        uint256 consBefore = stableToken.balanceOf(address(this));

        option.exercise(optBalance);

        // Option tokens burned
        assertEq(option.balanceOf(address(this)), 0);
        // Collateral received
        assertEq(shakyToken.balanceOf(address(this)) - collBefore, optBalance);
        // Consideration paid (strike=1e18, so 1:1)
        uint256 expectedCons = redemption.toConsideration(optBalance);
        assertEq(consBefore - stableToken.balanceOf(address(this)), expectedCons);
        // Collateral tokens unchanged
        assertGt(redemption.balanceOf(address(this)), 0);
    }

    function test_Redeem1() public {
        option.mint(1e18);
        uint256 optBalance = option.balanceOf(address(this));

        uint256 collBefore = shakyToken.balanceOf(address(this));
        option.burn(optBalance);

        // Both option and redemption burned
        assertEq(option.balanceOf(address(this)), 0);
        assertEq(redemption.balanceOf(address(this)), 0);
        // Collateral returned
        assertEq(shakyToken.balanceOf(address(this)) - collBefore, optBalance);
    }

    function test_RedeemConsideration1() public {
        option.mint(1e18);
        uint256 optBalance = option.balanceOf(address(this));

        // Exercise converts collateral→consideration inside redemption contract
        option.exercise(optBalance);

        uint256 consBefore = stableToken.balanceOf(address(this));
        uint256 redBalance = redemption.balanceOf(address(this));

        // Redeem via consideration (collateral was exercised away)
        redemption.redeemConsideration(redBalance);

        // Collateral tokens burned
        assertEq(redemption.balanceOf(address(this)), 0);
        // Consideration received
        uint256 expectedCons = redemption.toConsideration(redBalance);
        assertEq(stableToken.balanceOf(address(this)) - consBefore, expectedCons);
    }

    function test_ZeroAmountMint() public {
        vm.expectRevert(Option.InvalidValue.selector);
        option.mint(0);
    }

    function test_ZeroAmountExercise() public {
        option.mint(1);
        vm.expectRevert(Option.InvalidValue.selector);
        option.exercise(0);
    }

    function test_ZeroAmountRedeem() public {
        option.mint(1);
        vm.expectRevert(Rct.InvalidValue.selector);
        option.burn(0);
    }

    function test_InsufficientBalanceExercise() public {
        option.mint(1);
        vm.expectRevert();
        option.exercise(2);
    }

    function test_InsufficientBalanceRedeem() public {
        option.mint(1);
        vm.expectRevert(Option.InsufficientBalance.selector);
        option.burn(2);
    }

    function test_DoubleExercise() public {
        option.mint(1);
        option.exercise(1);
        vm.expectRevert();
        option.exercise(1);
    }

    function test_ExerciseAfterWindow() public {
        option.mint(1);
        // Default window is 8h; warp well past expiration + window.
        vm.warp(block.timestamp + 2 days);
        vm.expectRevert(Option.ExerciseWindowClosed.selector);
        option.exercise(1);
    }

    function test_ExerciseDuringWindow() public {
        option.mint(1);
        // Move just past expiration but inside the 8h window.
        vm.warp(block.timestamp + 1 days + 1 hours);
        option.exercise(1);
        assertEq(option.balanceOf(address(this)), 0);
    }

    function test_MintAfterExpiration() public {
        vm.warp(block.timestamp + 2 days);
        vm.expectRevert(Option.ContractExpired.selector);
        option.mint(1);
    }

    function test_PairRedeemAfterDeadlineReverts() public {
        // Past the exercise deadline, pair burn is closed — short side must use Receipt.redeem.
        option.mint(1);
        vm.warp(block.timestamp + 2 days);
        vm.expectRevert(Option.ExerciseWindowClosed.selector);
        option.burn(1);
    }

    function test_ShortRedeemAfterExpiration() public {
        option.mint(1e18);
        uint256 redBalance = redemption.balanceOf(address(this));
        uint256 collBefore = shakyToken.balanceOf(address(this));

        vm.warp(block.timestamp + 2 days);
        redemption.redeem(redBalance);

        // Collateral tokens burned
        assertEq(redemption.balanceOf(address(this)), 0);
        // Collateral returned
        assertEq(shakyToken.balanceOf(address(this)) - collBefore, redBalance);
    }

    function test_LockAndTransfer() public {
        option.mint(1);
        option.lock();
        vm.expectRevert(Option.LockedContract.selector);
        // forge-lint: disable-next-line(erc20-unchecked-transfer)
        IERC20(address(option)).transfer(address(0x123), 1);
    }

    function test_UnlockAndTransfer() public {
        option.mint(1);
        option.lock();
        option.unlock();
        safeTransfer(address(option), address(0x123), 1);
    }

    function test_BalancesOf() public {
        option.mint(1);
        Balances memory balances = option.balancesOf(address(this));
        assertEq(balances.option, 1);
        assertEq(balances.receipt, 1);
        assertGt(balances.collateral, 0);
        assertGt(balances.consideration, 0);
    }

    function test_Details() public view {
        OptionInfo memory info = option.details();
        assertEq(info.option, address(option));
        assertEq(info.receipt, address(redemption));
        assertEq(info.collateral.address_, shakyTokenAddr);
        assertEq(info.consideration.address_, stableTokenAddr);
        assertEq(info.strike, 1e18);
        assertFalse(info.isPut);
    }

    function test_CollateralData() public view {
        TokenData memory data = redemption.collateralData();
        assertEq(data.address_, shakyTokenAddr);
        assertEq(data.decimals, 18);
    }

    function test_ConsiderationData() public view {
        TokenData memory data = redemption.considerationData();
        assertEq(data.address_, stableTokenAddr);
        assertEq(data.decimals, 18);
    }

    function test_MultipleUsers() public {
        option.mint(10);
        safeTransfer(address(option), address(0x123), 5);

        stableToken.mint(address(0x123), 1000e18);

        vm.startPrank(address(0x123));
        approve1(shakyTokenAddr);
        approve1(stableTokenAddr);
        option.exercise(3);
        vm.stopPrank();

        assertEq(option.balanceOf(address(0x123)), 2);
    }

    function test_TransferChain() public {
        factory.enableAutoMintBurn(true); // opt-in for auto-redeem on receive
        option.mint(10);
        safeTransfer(address(option), address(0x123), 5);

        vm.prank(address(0x123));
        safeTransfer(address(option), address(0x456), 3);

        vm.prank(address(0x456));
        safeTransfer(address(option), address(this), 2);

        assertEq(option.balanceOf(address(this)), 5);
        assertEq(option.balanceOf(address(0x123)), 2);
        assertEq(option.balanceOf(address(0x456)), 1);
    }

    function test_Sweep() public {
        option.mint(1e18);
        uint256 redBalance = redemption.balanceOf(address(this));
        uint256 collBefore = shakyToken.balanceOf(address(this));

        vm.warp(block.timestamp + 2 days);
        redemption.sweep(address(this));

        assertEq(redemption.balanceOf(address(this)), 0);
        // Collateral returned via sweep
        assertEq(shakyToken.balanceOf(address(this)) - collBefore, redBalance);
    }

    function test_ToConsideration() public view {
        uint256 amount = 1e18;
        uint256 consAmount = redemption.toConsideration(amount);
        assertEq(consAmount, 1e18);
    }

    function test_ToCollateral() public view {
        uint256 consAmount = 1e18;
        uint256 amount = redemption.toCollateral(consAmount);
        assertEq(amount, 1e18);
    }

    function test_TransferAutoMint() public {
        factory.enableAutoMintBurn(true); // opt-in for auto-mint
        safeTransfer(address(option), address(0x123), 5);
        assertEq(option.balanceOf(address(0x123)), 5);
        // Fee-adjusted: mints slightly more to cover fee, so redemption balance >= 5
        assertGe(redemption.balanceOf(address(this)), 5);
    }

    function test_TransferFromAutoRedeem() public {
        factory.enableAutoMintBurn(true); // opt-in for auto-redeem on receive
        option.mint(10);
        safeTransfer(address(option), address(0x123), 5);

        vm.prank(address(0x123));
        IERC20(address(option)).approve(address(this), 3);

        uint256 shortBalanceBefore = redemption.balanceOf(address(this));
        safeTransferFrom(address(option), address(0x123), address(this), 3);
        uint256 shortBalanceAfter = redemption.balanceOf(address(this));

        assertEq(shortBalanceBefore - shortBalanceAfter, 3);
    }

    function test_ExerciseAllThenRedeem() public {
        option.mint(5);
        option.exercise(5);
        vm.expectRevert(Option.InsufficientBalance.selector);
        option.burn(1);
    }

    function test_ShortRedeemWithMixedCollateral() public {
        option.mint(10);
        option.exercise(6);

        vm.warp(block.timestamp + 2 days);
        redemption.redeem(10);
    }

    function test_RedeemConsiderationInsufficientBalance() public {
        approve1(shakyTokenAddr);
        approve1(stableTokenAddr);

        option.mint(10);

        vm.expectRevert(Rct.InsufficientConsideration.selector);
        redemption.redeemConsideration(10);
    }

    function test_MintToAddress() public {
        shakyToken.mint(address(0x123), 1000e18);

        vm.startPrank(address(0x123));
        approve1(shakyTokenAddr);
        option.mint(address(0x123), 5);
        vm.stopPrank();

        assertEq(option.balanceOf(address(0x123)), 5);
        assertEq(redemption.balanceOf(address(0x123)), 5);
    }

    function test_TransferBothTokensToSameAddress() public {
        option.mint(10);

        uint256 longBefore = option.balanceOf(address(this));
        uint256 shortBefore = redemption.balanceOf(address(this));

        safeTransfer(address(option), address(0x123), 5);

        assertEq(longBefore, 10);
        assertEq(shortBefore, 10);
        assertEq(option.balanceOf(address(0x123)), 5);
        assertEq(option.balanceOf(address(this)), 5);
        assertEq(redemption.balanceOf(address(0x123)), 0);
        assertEq(redemption.balanceOf(address(this)), 10);
    }

    function test_MultipleExerciseSessions() public {
        option.mint(10);
        option.exercise(2);
        option.exercise(3);
        option.exercise(1);

        assertEq(option.balanceOf(address(this)), 4);
    }

    function test_MultipleRedeemSessions() public {
        option.mint(10);
        option.burn(2);
        option.burn(3);
        option.burn(1);

        assertEq(option.balanceOf(address(this)), 4);
        assertEq(redemption.balanceOf(address(this)), 4);
    }

    function test_TransferFromWithApproval() public {
        option.mint(10);
        option.approve(address(0x123), 5);

        vm.prank(address(0x123));
        safeTransferFrom(address(option), address(this), address(0x456), 3);

        assertEq(option.balanceOf(address(0x456)), 3);
    }

    function test_ExerciseWithInsufficientConsideration() public {
        approve1(shakyTokenAddr);
        approve1(stableTokenAddr);

        option.mint(100);

        uint256 stableBalance = stableToken.balanceOf(address(this));
        safeTransfer(stableTokenAddr, address(0x999), stableBalance);

        vm.expectRevert(Rct.InsufficientConsideration.selector);
        option.exercise(100);
    }

    function test_LockPreventsTransferFrom() public {
        option.mint(10);
        safeTransfer(address(option), address(0x123), 5);

        vm.prank(address(0x123));
        approve1(address(option));

        option.lock();

        vm.expectRevert(Option.LockedContract.selector);
        // forge-lint: disable-next-line(erc20-unchecked-transfer)
        IERC20(address(option)).transferFrom(address(0x123), address(this), 3);
    }

    function test_FullLifecycle1() public {
        option.mint(10);
        safeTransfer(address(option), address(0x123), 5);
        safeTransfer(address(redemption), address(0x123), 5);

        stableToken.mint(address(0x123), 1000e18);

        vm.startPrank(address(0x123));
        approve1(shakyTokenAddr);
        approve1(stableTokenAddr);
        option.exercise(3);
        redemption.redeemConsideration(2);
        vm.stopPrank();

        assertEq(option.balanceOf(address(0x123)), 2);
        assertEq(redemption.balanceOf(address(0x123)), 3);
    }

    function test_FullLifecycle2() public {
        option.mint(10);
        safeTransfer(address(option), address(0x123), 5);

        vm.prank(address(0x123));
        safeTransfer(address(option), address(0x456), 3);

        option.burn(5);

        assertEq(option.balanceOf(address(this)), 0);
        assertEq(redemption.balanceOf(address(this)), 5);
        assertEq(option.balanceOf(address(0x123)), 2);
        assertEq(option.balanceOf(address(0x456)), 3);
    }

    function test_PostExpirationFlow() public {
        option.mint(10);
        safeTransfer(address(redemption), address(0x123), 5);

        vm.warp(block.timestamp + 10 days);

        redemption.redeem(5);

        vm.prank(address(0x123));
        redemption.redeem(5);

        assertEq(redemption.balanceOf(address(this)), 0);
        assertEq(redemption.balanceOf(address(0x123)), 0);
    }

    function test_DecimalConversionRoundtrip() public view {
        uint256 amount = 12345e18;
        uint256 consAmount = redemption.toConsideration(amount);
        uint256 backToAmount = redemption.toCollateral(consAmount);
        assertEq(amount, backToAmount);
    }

    function test_DirectShortTransfer() public {
        option.mint(10);
        safeTransfer(address(redemption), address(0x123), 5);

        assertEq(redemption.balanceOf(address(0x123)), 5);
        assertEq(redemption.balanceOf(address(this)), 5);
    }

    // ============ PUT OPTION TESTS ============

    function test_PutMintAndExercise() public {
        // Put: collateral=stableToken, consideration=shakyToken
        // Exercising a put = selling collateral at strike price
        address putAddr = factory.createOption(
            CreateParams({
                collateral: stableTokenAddr,
                consideration: shakyTokenAddr,
                expirationDate: uint40(block.timestamp + 1 days),
                strike: 1e18,
                isPut: true,
                isEuro: false,
                windowSeconds: 0
            })
        );
        Option putOption = Option(putAddr);
        Rct putReceipt = Rct(putOption.receipt());

        approve1(stableTokenAddr);
        approve1(shakyTokenAddr);

        // Mint deposits stableToken as collateral
        uint256 stableBefore = stableToken.balanceOf(address(this));
        putOption.mint(1e18);
        assertEq(stableBefore - stableToken.balanceOf(address(this)), 1e18);

        uint256 putBalance = putOption.balanceOf(address(this));
        assertGt(putBalance, 0);
        assertEq(putReceipt.balanceOf(address(this)), putBalance);

        // Exercise: pay shakyToken (consideration), receive stableToken (collateral)
        uint256 shakyBefore = shakyToken.balanceOf(address(this));
        stableBefore = stableToken.balanceOf(address(this));
        putOption.exercise(putBalance);

        assertEq(putOption.balanceOf(address(this)), 0);
        // Got collateral back
        assertEq(stableToken.balanceOf(address(this)) - stableBefore, putBalance);
        // Paid consideration
        uint256 expectedCons = putReceipt.toConsideration(putBalance);
        assertEq(shakyBefore - shakyToken.balanceOf(address(this)), expectedCons);
    }

    function test_PutNameDisplay() public {
        // Create put with strike=2000e18. For puts, name shows inverted: 1e36/2000e18 = 0.0005e18
        address putAddr = factory.createOption(
            CreateParams({
                collateral: stableTokenAddr,
                consideration: shakyTokenAddr,
                expirationDate: uint40(block.timestamp + 1 days),
                strike: 2000e18,
                isPut: true,
                isEuro: false,
                windowSeconds: 0
            })
        );
        Option putOption = Option(putAddr);

        assertTrue(putOption.isPut());
        string memory n = putOption.name();
        // Name should start with "OPT-" and contain token symbols
        bytes memory nb = bytes(n);
        assertGt(nb.length, 10);
        // Verify it starts with "OPTA-" (American)
        assertEq(nb[0], "O");
        assertEq(nb[1], "P");
        assertEq(nb[2], "T");
        assertEq(nb[3], "A");
        assertEq(nb[4], "-");
    }

    function test_PutRedeem() public {
        address putAddr = factory.createOption(
            CreateParams({
                collateral: stableTokenAddr,
                consideration: shakyTokenAddr,
                expirationDate: uint40(block.timestamp + 1 days),
                strike: 1e18,
                isPut: true,
                isEuro: false,
                windowSeconds: 0
            })
        );
        Option putOption = Option(putAddr);
        Rct putReceipt = Rct(putOption.receipt());

        approve1(stableTokenAddr);
        approve1(shakyTokenAddr);

        putOption.mint(1e18);
        uint256 putBalance = putOption.balanceOf(address(this));

        // Redeem returns collateral (stableToken) and burns both tokens
        uint256 stableBefore = stableToken.balanceOf(address(this));
        putOption.burn(putBalance);

        assertEq(putOption.balanceOf(address(this)), 0);
        assertEq(putReceipt.balanceOf(address(this)), 0);
        assertEq(stableToken.balanceOf(address(this)) - stableBefore, putBalance);
    }

    function test_PutPostExpirationRedeem() public {
        address putAddr = factory.createOption(
            CreateParams({
                collateral: stableTokenAddr,
                consideration: shakyTokenAddr,
                expirationDate: uint40(block.timestamp + 1 days),
                strike: 1e18,
                isPut: true,
                isEuro: false,
                windowSeconds: 0
            })
        );
        Option putOption = Option(putAddr);
        Rct putReceipt = Rct(putOption.receipt());

        approve1(stableTokenAddr);
        approve1(shakyTokenAddr);

        putOption.mint(1e18);
        uint256 redBalance = putReceipt.balanceOf(address(this));

        // Exercise half to create mixed collateral state
        uint256 half = redBalance / 2;
        putOption.exercise(half);

        // Expire and redeem remaining
        vm.warp(block.timestamp + 2 days);
        uint256 stableBefore = stableToken.balanceOf(address(this));
        putReceipt.redeem(putReceipt.balanceOf(address(this)));

        assertEq(putReceipt.balanceOf(address(this)), 0);
        // Should have received remaining collateral
        assertGt(stableToken.balanceOf(address(this)), stableBefore);
    }

    // ============ MIXED DECIMAL TESTS ============

    function test_MixedDecimals_6_18() public {
        // Create 6-decimal token
        Token6 token6 = new Token6();
        token6.mint(address(this), 1_000_000e6);
        address token6Addr = address(token6);

        // Create option: 6-decimal collateral, 18-decimal consideration
        address optAddr = factory.createOption(
            CreateParams({
                collateral: token6Addr,
                consideration: stableTokenAddr,
                expirationDate: uint40(block.timestamp + 1 days),
                strike: 2000e18,
                isPut: false,
                isEuro: false,
                windowSeconds: 0
            })
        );
        Option opt = Option(optAddr);
        Rct red = opt.receipt();

        // Approve
        IERC20(token6Addr).approve(factoryAddr, MAX256);
        factory.approve(token6Addr, MAX160);

        // Mint: deposit 1e6 (= 1 token with 6 decimals), 1:1 no fees
        opt.mint(1e6);
        assertEq(opt.balanceOf(address(this)), 1e6);

        // Verify conversion: 1 collateral token at strike 2000 = 2000 consideration tokens
        uint256 consAmount = red.toConsideration(1e6);
        assertEq(consAmount, 2000e18);

        // Verify inverse
        uint256 collAmount = red.toCollateral(2000e18);
        assertEq(collAmount, 1e6);
    }

    function test_MixedDecimals_18_6() public {
        Token6 token6 = new Token6();
        token6.mint(address(this), 1_000_000e6);
        address token6Addr = address(token6);

        // Create option: 18-decimal collateral, 6-decimal consideration
        address optAddr = factory.createOption(
            CreateParams({
                collateral: shakyTokenAddr,
                consideration: token6Addr,
                expirationDate: uint40(block.timestamp + 1 days),
                strike: 2000e18,
                isPut: false,
                isEuro: false,
                windowSeconds: 0
            })
        );
        Option opt = Option(optAddr);
        Rct red = opt.receipt();

        // Approve
        IERC20(token6Addr).approve(factoryAddr, MAX256);
        factory.approve(token6Addr, MAX160);

        // Verify conversion: 1e18 collateral at strike 2000 = 2000e6 consideration
        uint256 consAmount = red.toConsideration(1e18);
        assertEq(consAmount, 2000e6);

        uint256 collAmount = red.toCollateral(2000e6);
        assertEq(collAmount, 1e18);
    }

    function test_MixedDecimals_ExerciseFlow() public {
        Token6 token6 = new Token6();
        token6.mint(address(this), 1_000_000e6);
        address token6Addr = address(token6);

        // 18-decimal collateral, 6-decimal consideration, strike=2000
        address optAddr = factory.createOption(
            CreateParams({
                collateral: shakyTokenAddr,
                consideration: token6Addr,
                expirationDate: uint40(block.timestamp + 1 days),
                strike: 2000e18,
                isPut: false,
                isEuro: false,
                windowSeconds: 0
            })
        );
        Option opt = Option(optAddr);
        Rct red = opt.receipt();

        IERC20(token6Addr).approve(factoryAddr, MAX256);
        factory.approve(token6Addr, MAX160);

        // Mint 1e18 (1 full collateral token), 1:1 no fees
        opt.mint(1e18);
        uint256 optBalance = opt.balanceOf(address(this));

        // Exercise the amount we actually have
        uint256 token6Before = token6.balanceOf(address(this));
        opt.exercise(optBalance);
        uint256 token6After = token6.balanceOf(address(this));
        assertEq(opt.balanceOf(address(this)), 0);

        // Should have paid consideration: optBalance * 2000 (adjusted for decimals)
        uint256 expectedCons = red.toConsideration(optBalance);
        assertEq(token6Before - token6After, expectedCons);
    }

    // ============ NON-TRIVIAL STRIKE TESTS ============

    function test_Strike2000_Exercise() public {
        // ETH/USDC-like: strike=2000, both 18 decimals
        address optAddr = factory.createOption(
            CreateParams({
                collateral: shakyTokenAddr,
                consideration: stableTokenAddr,
                expirationDate: uint40(block.timestamp + 1 days),
                strike: 2000e18,
                isPut: false,
                isEuro: false,
                windowSeconds: 0
            })
        );
        Option opt = Option(optAddr);
        Rct red = opt.receipt();

        approve1(shakyTokenAddr);
        approve1(stableTokenAddr);

        // Mint 1e18 (1 option token), fee deducted
        opt.mint(1e18);
        uint256 optBalance = opt.balanceOf(address(this));

        // Exercise: pays strike * optBalance consideration
        uint256 stableBefore = stableToken.balanceOf(address(this));
        opt.exercise(optBalance);
        uint256 stableAfter = stableToken.balanceOf(address(this));

        uint256 expectedCons = red.toConsideration(optBalance);
        assertEq(stableBefore - stableAfter, expectedCons);
    }

    function test_Strike2000_ToConsideration() public {
        address optAddr = factory.createOption(
            CreateParams({
                collateral: shakyTokenAddr,
                consideration: stableTokenAddr,
                expirationDate: uint40(block.timestamp + 1 days),
                strike: 2000e18,
                isPut: false,
                isEuro: false,
                windowSeconds: 0
            })
        );
        Rct red = Option(optAddr).receipt();

        assertEq(red.toConsideration(1e18), 2000e18);
        assertEq(red.toConsideration(5e18), 10000e18);
    }

    function test_Strike2000_ToCollateral() public {
        address optAddr = factory.createOption(
            CreateParams({
                collateral: shakyTokenAddr,
                consideration: stableTokenAddr,
                expirationDate: uint40(block.timestamp + 1 days),
                strike: 2000e18,
                isPut: false,
                isEuro: false,
                windowSeconds: 0
            })
        );
        Rct red = Option(optAddr).receipt();

        assertEq(red.toCollateral(2000e18), 1e18);
        assertEq(red.toCollateral(10000e18), 5e18);
    }

    // ============ ACCESS CONTROL TESTS ============

    function test_NonOwnerCannotLock() public {
        vm.prank(address(0x123));
        vm.expectRevert();
        option.lock();
    }

    function test_NonOwnerCannotUnlock() public {
        option.lock();
        vm.prank(address(0x123));
        vm.expectRevert();
        option.unlock();
    }

    // ============ FACTORY ALLOWANCE TESTS ============

    function test_FactoryAllowanceDecrement() public {
        // Set specific allowance
        factory.approve(shakyTokenAddr, 1000);

        uint256 allowanceBefore = factory.allowance(shakyTokenAddr, address(this));
        assertEq(allowanceBefore, 1000);

        option.mint(500);

        uint256 allowanceAfter = factory.allowance(shakyTokenAddr, address(this));
        assertEq(allowanceAfter, 500);
    }

    function test_FactoryAllowanceInfinite() public {
        // MAX256 allowance should not be decremented
        factory.approve(shakyTokenAddr, MAX256);

        option.mint(1000);

        assertEq(factory.allowance(shakyTokenAddr, address(this)), MAX256);
    }

    function test_FactoryAllowanceInsufficient() public {
        // Set allowance too low
        factory.approve(shakyTokenAddr, 10);

        vm.expectRevert();
        option.mint(100);
    }

    // ============ NAME/SYMBOL TESTS ============

    function test_OptionNameFormat() public view {
        string memory n = option.name();
        bytes memory nb = bytes(n);

        // Format: "OPT[A|E]-{collSymbol}-{consSymbol}-{strike}-{date}"
        assertEq(nb[0], "O");
        assertEq(nb[1], "P");
        assertEq(nb[2], "T");
        assertEq(nb[3], "A");
        assertEq(nb[4], "-");
        // Symbol == name
        assertEq(option.symbol(), n);
        // Decimals match collateral
        assertEq(option.decimals(), 18);
    }

    function test_ReceiptNameFormat() public view {
        string memory n = redemption.name();
        bytes memory nb = bytes(n);

        // Format: "RCT-{collSymbol}-{consSymbol}-{strike}-{date}"
        assertEq(nb[0], "R");
        assertEq(nb[1], "C");
        assertEq(nb[2], "T");
        assertEq(nb[3], "-");
        assertEq(redemption.symbol(), n);
        assertEq(redemption.decimals(), 18);
    }

    // ============ EVENT EMISSION TESTS ============

    function test_MintEmitsEvent() public {
        vm.expectEmit(true, true, false, true);
        emit Option.Mint(address(option), address(this), 1);
        option.mint(1);
    }

    function test_ExerciseEmitsEvent() public {
        option.mint(1);
        vm.expectEmit(true, true, false, true);
        emit Option.Exercise(address(option), address(this), address(this), 1);
        option.exercise(1);
    }

    function test_LockEmitsEvent() public {
        vm.expectEmit(false, false, false, false);
        emit Option.ContractLocked();
        option.lock();
    }

    // ============ BATCH OPERATIONS ============

    function test_CreateOptionsBatch() public {
        CreateParams[] memory params = new CreateParams[](3);
        params[0] = CreateParams({
            collateral: shakyTokenAddr,
            consideration: stableTokenAddr,
            expirationDate: uint40(block.timestamp + 1 days),
            strike: 1e18,
            isPut: false,
            isEuro: false,
            windowSeconds: 0
        });
        params[1] = CreateParams({
            collateral: shakyTokenAddr,
            consideration: stableTokenAddr,
            expirationDate: uint40(block.timestamp + 7 days),
            strike: 2e18,
            isPut: false,
            isEuro: false,
            windowSeconds: 0
        });
        params[2] = CreateParams({
            collateral: shakyTokenAddr,
            consideration: stableTokenAddr,
            expirationDate: uint40(block.timestamp + 30 days),
            strike: 5e18,
            isPut: true,
            isEuro: false,
            windowSeconds: 0
        });

        address[] memory addrs = factory.createOptions(params);
        assertEq(addrs.length, 3);

        for (uint256 i = 0; i < 3; i++) {
            assertTrue(addrs[i] != address(0));
            assertTrue(factory.options(addrs[i]));
        }
    }

    // ============ FUZZ TESTS ============

    function testFuzz_MintAndRedeem(uint256 amount) public {
        amount = bound(amount, 1, 1_000_000e18);

        uint256 collBefore = shakyToken.balanceOf(address(this));
        option.mint(amount);

        uint256 optBalance = option.balanceOf(address(this));
        assertGt(optBalance, 0);

        option.burn(optBalance);

        // Both tokens zero
        assertEq(option.balanceOf(address(this)), 0);
        assertEq(redemption.balanceOf(address(this)), 0);
        // Collateral returned = optBalance (the non-fee portion)
        uint256 collAfter = shakyToken.balanceOf(address(this));
        // Net collateral loss = amount deposited - optBalance returned = fee amount
        assertEq(collBefore - collAfter, amount - optBalance);
    }

    function testFuzz_MintAndExercise(uint256 amount) public {
        amount = bound(amount, 1, 1_000_000e18);

        uint256 collBefore = shakyToken.balanceOf(address(this));
        uint256 consBefore = stableToken.balanceOf(address(this));

        option.mint(amount);
        uint256 optBalance = option.balanceOf(address(this));

        option.exercise(optBalance);

        // Options burned
        assertEq(option.balanceOf(address(this)), 0);
        // Net collateral: deposited `amount`, got back `optBalance` from exercise
        // So net loss = amount - optBalance (the fee)
        uint256 collAfter = shakyToken.balanceOf(address(this));
        assertEq(collBefore - collAfter, amount - optBalance);
        // Consideration paid = toConsideration(optBalance)
        uint256 expectedCons = redemption.toConsideration(optBalance);
        assertEq(consBefore - stableToken.balanceOf(address(this)), expectedCons);
    }

    function testFuzz_TransferAutoRedeem(uint256 mintAmt, uint256 transferAmt) public {
        mintAmt = bound(mintAmt, 2, 100_000e18);
        option.mint(mintAmt);
        uint256 optBalance = option.balanceOf(address(this));
        transferAmt = bound(transferAmt, 1, optBalance);

        uint256 redBefore = redemption.balanceOf(address(this));

        safeTransfer(address(option), address(0x123), transferAmt);

        // Recipient got options
        assertEq(option.balanceOf(address(0x123)), transferAmt);
        // Sender's option balance decreased
        assertEq(option.balanceOf(address(this)), optBalance - transferAmt);
        // Collateral unchanged (recipient has no redemptions to auto-redeem)
        assertEq(redemption.balanceOf(address(this)), redBefore);
    }

    // ============ EDGE CASE & SECURITY TESTS ============

    function test_CreateOptionSameTokenReverts() public {
        vm.expectRevert(Factory.InvalidTokens.selector);
        factory.createOption(
            CreateParams({
                collateral: shakyTokenAddr,
                consideration: shakyTokenAddr,
                expirationDate: uint40(block.timestamp + 1 days),
                strike: 1e18,
                isPut: false,
                isEuro: false,
                windowSeconds: 0
            })
        );
    }

    function test_CreateOptionPastExpirationReverts() public {
        vm.expectRevert(Rct.InvalidValue.selector);
        factory.createOption(
            CreateParams({
                collateral: shakyTokenAddr,
                consideration: stableTokenAddr,
                expirationDate: uint40(block.timestamp - 1),
                strike: 1e18,
                isPut: false,
                isEuro: false,
                windowSeconds: 0
            })
        );
    }

    function test_CreateOptionZeroStrikeReverts() public {
        vm.expectRevert(Rct.InvalidValue.selector);
        factory.createOption(
            CreateParams({
                collateral: shakyTokenAddr,
                consideration: stableTokenAddr,
                expirationDate: uint40(block.timestamp + 1 days),
                strike: 0,
                isPut: false,
                isEuro: false,
                windowSeconds: 0
            })
        );
    }

    function test_ReinitCloneReverts() public {
        // Cloned option is already initialized — calling init again should revert
        vm.expectRevert();
        option.init(address(redemption), address(this));
    }

    function test_ReinitCollateralCloneReverts() public {
        vm.prank(address(option));
        vm.expectRevert();
        redemption.init(
            shakyTokenAddr,
            stableTokenAddr,
            uint40(block.timestamp + 1 days),
            1e18,
            false,
            false,
            uint40(8 hours),
            address(option),
            factoryAddr
        );
    }

    function test_LockPreventsExercise() public {
        option.mint(1e18);
        option.lock();

        vm.expectRevert(Option.LockedContract.selector);
        option.exercise(1);
    }

    function test_LockPreventsMint() public {
        option.lock();

        vm.expectRevert(Option.LockedContract.selector);
        option.mint(1);
    }

    function test_LockPreventsRedeem() public {
        option.mint(1e18);
        option.lock();

        vm.expectRevert(Option.LockedContract.selector);
        option.burn(1);
    }

    function test_LockPreventsCollateralRedeem() public {
        option.mint(1e18);
        option.lock();
        vm.warp(block.timestamp + 2 days);

        vm.expectRevert(Rct.LockedContract.selector);
        redemption.redeem(1);
    }

    function test_BatchSweepMultipleUsers() public {
        option.mint(100e18);
        uint256 redBalance = redemption.balanceOf(address(this));

        // Distribute redemption tokens to multiple users
        safeTransfer(address(redemption), address(0x111), redBalance / 3);
        safeTransfer(address(redemption), address(0x222), redBalance / 3);

        vm.warp(block.timestamp + 2 days);

        address[] memory holders = new address[](3);
        holders[0] = address(this);
        holders[1] = address(0x111);
        holders[2] = address(0x222);

        redemption.sweep(holders);

        assertEq(redemption.balanceOf(address(this)), 0);
        assertEq(redemption.balanceOf(address(0x111)), 0);
        assertEq(redemption.balanceOf(address(0x222)), 0);
    }

    function test_ApproveOperator() public {
        address operator = address(0x789);

        factory.approveOperator(operator, true);
        assertTrue(factory.approvedOperator(address(this), operator));

        // Operator can transfer option tokens without individual approval
        option.mint(10e18);
        uint256 optBalance = option.balanceOf(address(this));

        vm.prank(operator);
        // forge-lint: disable-next-line(erc20-unchecked-transfer)
        option.transferFrom(address(this), address(0x123), optBalance / 2);

        assertEq(option.balanceOf(address(0x123)), optBalance / 2);

        // Revoke
        factory.approveOperator(operator, false);
        assertFalse(factory.approvedOperator(address(this), operator));
    }

    function test_ApproveOperatorCannotApproveSelf() public {
        vm.expectRevert(Factory.InvalidAddress.selector);
        factory.approveOperator(address(this), true);
    }

    function test_FactoryTransferFromNonCollateral() public {
        // Non-redemption contract cannot call factory.transferFrom
        vm.expectRevert(Factory.InvalidAddress.selector);
        factory.transferFrom(address(this), address(0x123), 100, shakyTokenAddr);
    }

    function test_ShortRedeemMixedCollateralExactAmounts() public {
        // Mint 10 options, exercise 6 — redemption holds 4 collateral + consideration from 6
        option.mint(10e18);
        uint256 optBalance = option.balanceOf(address(this));
        uint256 sixTokens = (optBalance * 6) / 10;

        option.exercise(sixTokens);

        vm.warp(block.timestamp + 2 days);

        uint256 redBalance = redemption.balanceOf(address(this));
        uint256 collBefore = shakyToken.balanceOf(address(this));
        uint256 consBefore = stableToken.balanceOf(address(this));

        // Pro-rata: gets proportional collateral + consideration for remainder
        redemption.redeem(redBalance);

        // Should have received both collateral and consideration
        uint256 collReceived = shakyToken.balanceOf(address(this)) - collBefore;
        uint256 consReceived = stableToken.balanceOf(address(this)) - consBefore;

        assertGt(collReceived, 0);
        assertGt(consReceived, 0);
        assertEq(redemption.balanceOf(address(this)), 0);
    }

    function test_ExerciseThenTransferCollateralThenRedeem() public {
        // User A mints, exercises some, transfers redemption to User B
        // User B redeems post-expiration and gets mixed assets
        option.mint(10e18);
        uint256 optBalance = option.balanceOf(address(this));
        option.exercise(optBalance / 2);

        uint256 redBalance = redemption.balanceOf(address(this));
        safeTransfer(address(redemption), address(0x777), redBalance);

        vm.warp(block.timestamp + 2 days);

        uint256 collBefore = shakyToken.balanceOf(address(0x777));
        vm.prank(address(0x777));
        redemption.redeem(redBalance);

        // User B got collateral
        assertGt(shakyToken.balanceOf(address(0x777)) - collBefore, 0);
        assertEq(redemption.balanceOf(address(0x777)), 0);
    }
}

/// @notice 6-decimal test token for mixed decimal tests
contract Token6 is ERC20 {
    constructor() ERC20("Token6", "T6") { }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function decimals() public pure override returns (uint8) {
        return 6;
    }
}
