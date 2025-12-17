// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { Test, console } from "forge-std/Test.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { OptionFactory, Redemption, Option, OptionParameter } from "../contracts/OptionFactory.sol";
import { OptionBase } from "../contracts/OptionBase.sol";
import { Balances } from "../contracts/Option.sol";
import { StableToken } from "../contracts/StableToken.sol";
import { ShakyToken } from "../contracts/ShakyToken.sol";
import { IPermit2 } from "../contracts/interfaces/IPermit2.sol";

contract OptionTest is Test {
    using SafeERC20 for IERC20;

    StableToken public stableToken;
    ShakyToken public shakyToken;
    Redemption public redemptionClone;
    Option public optionClone;
    OptionFactory public factory;

    IPermit2 permit2 = IPermit2(PERMIT2);
    Option option;
    Redemption redemption;
    address shakyToken_;
    address stableToken_;
    address factory_;

    // Unichain RPC URL - replace with actual Unichain RPC endpoint
    string constant UNICHAIN_RPC_URL = "https://unichain.drpc.org";
    address constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;

    uint160 constant MAX160 = type(uint160).max;
    uint48 constant MAX48 = type(uint48).max;
    uint256 constant MAX256 = type(uint256).max;

    function setUp() public {
        // Fork Unichain at the latest block
        vm.createSelectFork(UNICHAIN_RPC_URL);

        // Deploy tokens
        stableToken = new StableToken();
        shakyToken = new ShakyToken();
        shakyToken_ = address(shakyToken);
        stableToken_ = address(stableToken);

        // Mint tokens to test address
        stableToken.mint(address(this), 1_000_000 * 10 ** 18);
        shakyToken.mint(address(this), 1_000_000 * 10 ** 18);

        // Deploy ShortOption
        redemptionClone = new Redemption(
            "Short Option", "SHORT", address(stableToken), address(shakyToken), block.timestamp + 1 days, 100, false
        );

        // Deploy LongOption
        optionClone = new Option(
            "Long Option",
            "LONG",
            address(stableToken),
            address(shakyToken),
            block.timestamp + 1 days,
            100,
            false,
            address(redemptionClone)
        );

        // Deploy OptionFactory
        factory = new OptionFactory(address(redemptionClone), address(optionClone), PERMIT2, 0.0001e18);
        factory_ = address(factory);

        // OptionParameter[] memory options = new OptionParameter[](1);
        // options[0] = OptionParameter({
        //     longSymbol: "LONG",
        //     shortSymbol: "SHORT",
        //     collateral: address(weth),
        //     consideration: address(usdc),
        //     expiration: block.timestamp + 1 days,
        //     strike: 100,
        //     isPut: false
        // });

        // factory.createOptions(options);

        OptionParameter[] memory options = new OptionParameter[](1);
        options[0] = OptionParameter({
            optionSymbol: "LONG",
            redemptionSymbol: "SHORT",
            collateral_: address(shakyToken),
            consideration_: address(stableToken),
            expiration: block.timestamp + 1 days,
            strike: 1e18,
            isPut: false
        });

        factory.createOptions(options);

        address[] memory options1 = factory.getOptions();
        option = Option(options1[0]);

        redemption = option.redemption();

        approve1(shakyToken_, address(factory));
        approve1(stableToken_, address(factory));
    }

    function approve1(address token, address spender) public {
        IERC20(token).approve(PERMIT2, MAX256);
        permit2.approve(token, spender, MAX160, MAX48);
    }

    function approve2(address token, address spender) public {
        IERC20(token).approve(spender, MAX256);
    }

    function safeTransfer(address token, address to, uint256 amount) internal {
        IERC20(token).safeTransfer(to, amount);
    }

    function safeTransferFrom(address token, address from, address to, uint256 amount) internal {
        IERC20(token).safeTransferFrom(from, to, amount);
    }

    function consoleBalances() public view {
        console.log("ShakyToken balance:", shakyToken.balanceOf(address(this)));
        console.log("StableToken balance:", stableToken.balanceOf(address(this)));
        console.log("LongOption balance:", option.balanceOf(address(this)));
        console.log("ShortOption balance:", redemption.balanceOf(address(this)));
    }

    modifier t1() {
        approve1(shakyToken_, address(factory));
        approve1(stableToken_, address(factory));
        _;
        consoleBalances();
    }

    modifier t2() {
        approve2(shakyToken_, address(factory));
        approve2(stableToken_, address(factory));
        _;
        consoleBalances();
    }

    function test_Mint() public t1 {
        option.mint(1);
    }

    function test_Transfer1() public t1 {
        safeTransfer(address(option), address(0x123), 1);
    }

    function test_Transfer2() public t2 {
        safeTransfer(address(option), address(0x123), 1);
    }

    function test_TransferFrom1() public t1 {
        safeTransfer(address(option), address(0x123), 1);
        vm.prank(address(0x123));
        approve2(address(option), address(this));
        safeTransferFrom(address(option), address(0x123), address(this), 1);
    }

    function test_TransferTransfer() public t1 {
        safeTransfer(address(option), address(0x123), 1);
        vm.prank(address(0x123));
        safeTransfer(address(option), address(this), 1);
    }

    function test_Exercise1() public t1 {
        option.mint(1);
        option.exercise(1);
    }

    function test_Exercise2() public t2 {
        option.mint(1);
        option.exercise(1);
    }

    function test_Redeem1() public t1 {
        option.mint(1);
        option.redeem(1);
    }

    function test_Redeem2() public t2 {
        option.mint(1);
        option.redeem(1);
    }

    function test_RedeemConsideration1() public t1 {
        option.mint(1);
        option.exercise(1);
        redemption.redeemConsideration(1);
    }

    function test_RedeemConsideration2() public t2 {
        option.mint(1);
        option.exercise(1);
        redemption.redeemConsideration(1);
    }

    function test_ZeroAmountMint() public t1 {
        vm.expectRevert();
        option.mint(0);
    }

    function test_ZeroAmountExercise() public t1 {
        option.mint(1);
        vm.expectRevert();
        option.exercise(0);
    }

    function test_ZeroAmountRedeem() public t1 {
        option.mint(1);
        vm.expectRevert();
        option.redeem(0);
    }

    function test_InsufficientBalanceExercise() public t1 {
        option.mint(1);
        vm.expectRevert();
        option.exercise(2);
    }

    function test_InsufficientBalanceRedeem() public t1 {
        option.mint(1);
        vm.expectRevert();
        option.redeem(2);
    }

    function test_DoubleExercise() public t1 {
        option.mint(1);
        option.exercise(1);
        vm.expectRevert();
        option.exercise(1);
    }

    function test_ExerciseAfterExpiration() public t1 {
        option.mint(1);
        vm.warp(block.timestamp + 2 days);
        vm.expectRevert();
        option.exercise(1);
    }

    function test_MintAfterExpiration() public t1 {
        vm.warp(block.timestamp + 2 days);
        vm.expectRevert();
        option.mint(1);
    }

    function test_RedeemAfterExpiration() public t1 {
        option.mint(1);
        vm.warp(block.timestamp + 2 days);
        vm.expectRevert();
        option.redeem(1);
    }

    function test_ShortRedeemAfterExpiration() public t1 {
        option.mint(1);
        vm.warp(block.timestamp + 2 days);
        redemption.redeem(1);
    }

    function test_LockAndTransfer() public t1 {
        option.mint(1);
        option.lock();
        vm.expectRevert();
        IERC20(address(option)).transfer(address(0x123), 1);
    }

    function test_UnlockAndTransfer() public t1 {
        option.mint(1);
        option.lock();
        option.unlock();
        safeTransfer(address(option), address(0x123), 1);
    }

    function test_BalancesOf() public t1 {
        option.mint(1);
        Balances memory balances = option.balancesOf(address(this));
        assertEq(balances.option, 1);
        assertEq(balances.redemption, 1);
        assertGt(balances.collateral, 0);
        assertGt(balances.consideration, 0);
    }

    function test_Details() public view {
        option.details();
    }

    function test_CollateralData() public view {
        redemption.collateralData();
    }

    function test_ConsiderationData() public view {
        redemption.considerationData();
    }

    function test_RedeemWithAddress() public t1 {
        option.mint(1);
        option.redeem(address(this), 1);
    }

    function test_PartialExerciseAndRedeem() public t1 {
        option.mint(10);
        option.exercise(5);
        option.redeem(5);
    }

    function test_MultipleUsers() public t1 {
        option.mint(10);
        safeTransfer(address(option), address(0x123), 5);

        stableToken.mint(address(0x123), 1000e18);

        vm.startPrank(address(0x123));
        approve1(shakyToken_, address(factory));
        approve1(stableToken_, address(factory));
        option.exercise(3);
        vm.stopPrank();

        assertEq(option.balanceOf(address(0x123)), 2);
    }

    function test_TransferChain() public t1 {
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

    function test_Sweep() public t1 {
        option.mint(5);
        vm.warp(block.timestamp + 2 days);
        redemption.sweep(address(this));
        assertEq(redemption.balanceOf(address(this)), 0);
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

    function test_TransferAutoMint() public t1 {
        safeTransfer(address(option), address(0x123), 5);
        assertEq(option.balanceOf(address(0x123)), 5);
        assertEq(redemption.balanceOf(address(this)), 5);
    }

    function test_TransferFromAutoRedeem() public t1 {
        option.mint(10);
        safeTransfer(address(option), address(0x123), 5);

        vm.prank(address(0x123));
        approve2(address(option), address(this));

        uint256 shortBalanceBefore = redemption.balanceOf(address(this));
        safeTransferFrom(address(option), address(0x123), address(this), 3);
        uint256 shortBalanceAfter = redemption.balanceOf(address(this));

        assertEq(shortBalanceBefore - shortBalanceAfter, 3);
    }

    function test_ExerciseAllThenRedeem() public t1 {
        option.mint(5);
        option.exercise(5);
        vm.expectRevert();
        option.redeem(1);
    }

    function test_ShortRedeemWithMixedCollateral() public t1 {
        option.mint(10);
        option.exercise(6);

        vm.warp(block.timestamp + 2 days);
        redemption.redeem(10);
    }

    function test_RedeemConsiderationInsufficientBalance() public {
        approve1(shakyToken_, address(factory));
        approve1(stableToken_, address(factory));

        option.mint(10);

        vm.expectRevert(OptionBase.InsufficientConsideration.selector);
        redemption.redeemConsideration(10);
    }

    function test_MintToAddress() public {
        shakyToken.mint(address(0x123), 1000e18);

        vm.startPrank(address(0x123));
        approve1(shakyToken_, address(factory));
        option.mint(address(0x123), 5);
        vm.stopPrank();

        assertEq(option.balanceOf(address(0x123)), 5);
        assertEq(redemption.balanceOf(address(0x123)), 5);
    }

    function test_TransferBothTokensToSameAddress() public t1 {
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

    function test_MultipleExerciseSessions() public t1 {
        option.mint(10);
        option.exercise(2);
        option.exercise(3);
        option.exercise(1);

        assertEq(option.balanceOf(address(this)), 4);
    }

    function test_MultipleRedeemSessions() public t1 {
        option.mint(10);
        option.redeem(2);
        option.redeem(3);
        option.redeem(1);

        assertEq(option.balanceOf(address(this)), 4);
        assertEq(redemption.balanceOf(address(this)), 4);
    }

    function test_TransferFromWithApproval() public t1 {
        option.mint(10);
        option.approve(address(0x123), 5);

        vm.prank(address(0x123));
        safeTransferFrom(address(option), address(this), address(0x456), 3);

        assertEq(option.balanceOf(address(0x456)), 3);
    }

    function test_ExerciseWithInsufficientConsideration() public {
        approve1(shakyToken_, factory_);
        approve1(stableToken_, factory_);

        option.mint(100);

        uint256 stableBalance = stableToken.balanceOf(address(this));

        // stableToken.transfer(address(0x999), stableBalance);
        safeTransfer(stableToken_, address(0x999), stableBalance);

        vm.expectRevert();
        option.exercise(100);
    }

    function test_LockPreventsTransferFrom() public t1 {
        option.mint(10);
        safeTransfer(address(option), address(0x123), 5);

        vm.prank(address(0x123));
        approve2(address(option), address(this));

        option.lock();

        vm.expectRevert();
        IERC20(address(option)).transferFrom(address(0x123), address(this), 3);
    }

    function test_FullLifecycle1() public t1 {
        option.mint(10);
        safeTransfer(address(option), address(0x123), 5);
        safeTransfer(address(redemption), address(0x123), 5);

        stableToken.mint(address(0x123), 1000e18);

        vm.startPrank(address(0x123));
        approve1(shakyToken_, address(factory));
        approve1(stableToken_, address(factory));
        option.exercise(3);
        redemption.redeemConsideration(2);
        vm.stopPrank();

        assertEq(option.balanceOf(address(0x123)), 2);
        assertEq(redemption.balanceOf(address(0x123)), 3);
    }

    function test_FullLifecycle2() public t1 {
        option.mint(10);
        safeTransfer(address(option), address(0x123), 5);

        vm.prank(address(0x123));
        safeTransfer(address(option), address(0x456), 3);

        option.redeem(5);

        assertEq(option.balanceOf(address(this)), 0);
        assertEq(redemption.balanceOf(address(this)), 5);
        assertEq(option.balanceOf(address(0x123)), 2);
        assertEq(option.balanceOf(address(0x456)), 3);
    }

    function test_PostExpirationFlow() public t1 {
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

    function test_ShortOptionSweepMultipleUsers() public t1 {
        option.mint(10);

        vm.warp(block.timestamp + 2 days);

        redemption.sweep(address(this));

        assertEq(redemption.balanceOf(address(this)), 0);
    }

    function test_DirectShortTransfer() public t1 {
        option.mint(10);
        safeTransfer(address(redemption), address(0x123), 5);

        assertEq(redemption.balanceOf(address(0x123)), 5);
        assertEq(redemption.balanceOf(address(this)), 5);
    }
}

contract OptionFunctionsTest is Test {
    using SafeERC20 for IERC20;

    StableToken public stableToken;
    ShakyToken public shakyToken;
    Redemption public redemptionClone;
    Option public optionClone;
    OptionFactory public factory;

    IPermit2 permit2 = IPermit2(PERMIT2);
    Option option;
    Redemption redemption;
    address shakyToken_;
    address stableToken_;
    address factory_;

    // Unichain RPC URL - replace with actual Unichain RPC endpoint
    string constant UNICHAIN_RPC_URL = "https://unichain.drpc.org";
    address constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;

    uint160 constant MAX160 = type(uint160).max;
    uint48 constant MAX48 = type(uint48).max;
    uint256 constant MAX256 = type(uint256).max;

    function setUp() public {
        // Fork Unichain at the latest block
        vm.createSelectFork(UNICHAIN_RPC_URL);

        // Deploy tokens
        stableToken = new StableToken();
        shakyToken = new ShakyToken();
        shakyToken_ = address(shakyToken);
        stableToken_ = address(stableToken);

        // Mint tokens to test address
        stableToken.mint(address(this), 1_000_000 * 10 ** 18);
        shakyToken.mint(address(this), 1_000_000 * 10 ** 18);

        // Deploy ShortOption
        redemptionClone = new Redemption(
            "Short Option", "SHORT", address(stableToken), address(shakyToken), block.timestamp + 1 days, 100, false
        );

        // Deploy LongOption
        optionClone = new Option(
            "Long Option",
            "LONG",
            address(stableToken),
            address(shakyToken),
            block.timestamp + 1 days,
            100,
            false,
            address(redemptionClone)
        );

        // Deploy OptionFactory
        factory = new OptionFactory(address(redemptionClone), address(optionClone), PERMIT2, 0.0001e18);
        factory_ = address(factory);

        // OptionParameter[] memory options = new OptionParameter[](1);
        // options[0] = OptionParameter({
        //     longSymbol: "LONG",
        //     shortSymbol: "SHORT",
        //     collateral: address(weth),
        //     consideration: address(usdc),
        //     expiration: block.timestamp + 1 days,
        //     strike: 100,
        //     isPut: false
        // });

        // factory.createOptions(options);

        OptionParameter[] memory options = new OptionParameter[](1);
        options[0] = OptionParameter({
            optionSymbol: "LONG",
            redemptionSymbol: "SHORT",
            collateral_: address(shakyToken),
            consideration_: address(stableToken),
            expiration: block.timestamp + 1 days,
            strike: 1e18,
            isPut: false
        });

        factory.createOptions(options);

        address[] memory options1 = factory.getOptions();
        option = Option(options1[0]);

        redemption = option.redemption();

        approve1(shakyToken_, address(factory));
        approve1(stableToken_, address(factory));
    }

    function approve1(address token, address spender) public {
        IERC20(token).approve(PERMIT2, MAX256);
        permit2.approve(token, spender, MAX160, MAX48);
    }

    function approve2(address token, address spender) public {
        IERC20(token).approve(spender, MAX256);
    }

    function safeTransfer(address token, address to, uint256 amount) internal {
        IERC20(token).safeTransfer(to, amount);
    }

    function safeTransferFrom(address token, address from, address to, uint256 amount) internal {
        IERC20(token).safeTransferFrom(from, to, amount);
    }

    function consoleBalances() public view {
        console.log("ShakyToken balance:", shakyToken.balanceOf(address(this)));
        console.log("StableToken balance:", stableToken.balanceOf(address(this)));
        console.log("LongOption balance:", option.balanceOf(address(this)));
        console.log("ShortOption balance:", redemption.balanceOf(address(this)));
    }

    modifier t1() {
        approve1(shakyToken_, address(factory));
        approve1(stableToken_, address(factory));
        _;
        consoleBalances();
    }

    modifier t2() {
        approve2(shakyToken_, address(factory));
        approve2(stableToken_, address(factory));
        _;
        consoleBalances();
    }

    function test_Mint() public t1 {
        option.mint(1);
    }

    function test_Transfer1() public t1 {
        safeTransfer(address(option), address(0x123), 1);
    }

    function test_Transfer2() public t2 {
        safeTransfer(address(option), address(0x123), 1);
    }

    function test_TransferFrom1() public t1 {
        safeTransfer(address(option), address(0x123), 1);
        vm.prank(address(0x123));
        approve2(address(option), address(this));
        safeTransferFrom(address(option), address(0x123), address(this), 1);
    }

    function test_TransferTransfer() public t1 {
        safeTransfer(address(option), address(0x123), 1);
        vm.prank(address(0x123));
        safeTransfer(address(option), address(this), 1);
    }

    function test_Exercise1() public t1 {
        option.mint(1);
        option.exercise(1);
    }

    function test_Exercise2() public t2 {
        option.mint(1);
        option.exercise(1);
    }

    function test_Redeem1() public t1 {
        option.mint(1);
        option.redeem(1);
    }

    function test_Redeem2() public t2 {
        option.mint(1);
        option.redeem(1);
    }

    function test_RedeemConsideration1() public t1 {
        option.mint(1);
        option.exercise(1);
        redemption.redeemConsideration(1);
    }

    function test_RedeemConsideration2() public t2 {
        option.mint(1);
        option.exercise(1);
        redemption.redeemConsideration(1);
    }

    function test_ZeroAmountMint() public t1 {
        vm.expectRevert();
        option.mint(0);
    }

    function test_ZeroAmountExercise() public t1 {
        option.mint(1);
        vm.expectRevert();
        option.exercise(0);
    }

    function test_ZeroAmountRedeem() public t1 {
        option.mint(1);
        vm.expectRevert();
        option.redeem(0);
    }

    function test_InsufficientBalanceExercise() public t1 {
        option.mint(1);
        vm.expectRevert();
        option.exercise(2);
    }

    function test_InsufficientBalanceRedeem() public t1 {
        option.mint(1);
        vm.expectRevert();
        option.redeem(2);
    }

    function test_DoubleExercise() public t1 {
        option.mint(1);
        option.exercise(1);
        vm.expectRevert();
        option.exercise(1);
    }

    function test_ExerciseAfterExpiration() public t1 {
        option.mint(1);
        vm.warp(block.timestamp + 2 days);
        vm.expectRevert();
        option.exercise(1);
    }

    function test_MintAfterExpiration() public t1 {
        vm.warp(block.timestamp + 2 days);
        vm.expectRevert();
        option.mint(1);
    }

    function test_RedeemAfterExpiration() public t1 {
        option.mint(1);
        vm.warp(block.timestamp + 2 days);
        vm.expectRevert();
        option.redeem(1);
    }

    function test_ShortRedeemAfterExpiration() public t1 {
        option.mint(1);
        vm.warp(block.timestamp + 2 days);
        redemption.redeem(1);
    }

    function test_LockAndTransfer() public t1 {
        option.mint(1);
        option.lock();
        vm.expectRevert();
        IERC20(address(option)).transfer(address(0x123), 1);
    }

    function test_UnlockAndTransfer() public t1 {
        option.mint(1);
        option.lock();
        option.unlock();
        safeTransfer(address(option), address(0x123), 1);
    }

    function test_BalancesOf() public t1 {
        option.mint(1);
        Balances memory balances = option.balancesOf(address(this));
        assertEq(balances.option, 1);
        assertEq(balances.redemption, 1);
        assertGt(balances.collateral, 0);
        assertGt(balances.consideration, 0);
    }

    function test_Details() public view {
        option.details();
    }

    function test_CollateralData() public view {
        redemption.collateralData();
    }

    function test_ConsiderationData() public view {
        redemption.considerationData();
    }

    function test_RedeemWithAddress() public t1 {
        option.mint(1);
        option.redeem(address(this), 1);
    }

    function test_PartialExerciseAndRedeem() public t1 {
        option.mint(10);
        option.exercise(5);
        option.redeem(5);
    }

    function test_MultipleUsers() public t1 {
        option.mint(10);
        safeTransfer(address(option), address(0x123), 5);

        stableToken.mint(address(0x123), 1000e18);

        vm.startPrank(address(0x123));
        approve1(shakyToken_, address(factory));
        approve1(stableToken_, address(factory));
        option.exercise(3);
        vm.stopPrank();

        assertEq(option.balanceOf(address(0x123)), 2);
    }

    function test_TransferChain() public t1 {
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

    function test_Sweep() public t1 {
        option.mint(5);
        vm.warp(block.timestamp + 2 days);
        redemption.sweep(address(this));
        assertEq(redemption.balanceOf(address(this)), 0);
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

    function test_TransferAutoMint() public t1 {
        safeTransfer(address(option), address(0x123), 5);
        assertEq(option.balanceOf(address(0x123)), 5);
        assertEq(redemption.balanceOf(address(this)), 5);
    }

    function test_TransferFromAutoRedeem() public t1 {
        option.mint(10);
        safeTransfer(address(option), address(0x123), 5);

        vm.prank(address(0x123));
        approve2(address(option), address(this));

        uint256 shortBalanceBefore = redemption.balanceOf(address(this));
        safeTransferFrom(address(option), address(0x123), address(this), 3);
        uint256 shortBalanceAfter = redemption.balanceOf(address(this));

        assertEq(shortBalanceBefore - shortBalanceAfter, 3);
    }

    function test_ExerciseAllThenRedeem() public t1 {
        option.mint(5);
        option.exercise(5);
        vm.expectRevert();
        option.redeem(1);
    }

    function test_ShortRedeemWithMixedCollateral() public t1 {
        option.mint(10);
        option.exercise(6);

        vm.warp(block.timestamp + 2 days);
        redemption.redeem(10);
    }

    function test_RedeemConsiderationInsufficientBalance() public {
        approve1(shakyToken_, address(factory));
        approve1(stableToken_, address(factory));

        option.mint(10);

        vm.expectRevert(OptionBase.InsufficientConsideration.selector);
        redemption.redeemConsideration(10);
    }

    function test_MintToAddress() public {
        shakyToken.mint(address(0x123), 1000e18);

        vm.startPrank(address(0x123));
        approve1(shakyToken_, address(factory));
        option.mint(address(0x123), 5);
        vm.stopPrank();

        assertEq(option.balanceOf(address(0x123)), 5);
        assertEq(redemption.balanceOf(address(0x123)), 5);
    }

    function test_TransferBothTokensToSameAddress() public t1 {
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

    function test_MultipleExerciseSessions() public t1 {
        option.mint(10);
        option.exercise(2);
        option.exercise(3);
        option.exercise(1);

        assertEq(option.balanceOf(address(this)), 4);
    }

    function test_MultipleRedeemSessions() public t1 {
        option.mint(10);
        option.redeem(2);
        option.redeem(3);
        option.redeem(1);

        assertEq(option.balanceOf(address(this)), 4);
        assertEq(redemption.balanceOf(address(this)), 4);
    }

    function test_TransferFromWithApproval() public t1 {
        option.mint(10);
        option.approve(address(0x123), 5);

        vm.prank(address(0x123));
        safeTransferFrom(address(option), address(this), address(0x456), 3);

        assertEq(option.balanceOf(address(0x456)), 3);
    }

    function test_ExerciseWithInsufficientConsideration() public {
        approve1(shakyToken_, factory_);
        approve1(stableToken_, factory_);

        option.mint(100);

        uint256 stableBalance = stableToken.balanceOf(address(this));

        // stableToken.transfer(address(0x999), stableBalance);
        safeTransfer(stableToken_, address(0x999), stableBalance);

        vm.expectRevert();
        option.exercise(100);
    }

    function test_LockPreventsTransferFrom() public t1 {
        option.mint(10);
        safeTransfer(address(option), address(0x123), 5);

        vm.prank(address(0x123));
        approve2(address(option), address(this));

        option.lock();

        vm.expectRevert();
        IERC20(address(option)).transferFrom(address(0x123), address(this), 3);
    }

    function test_FullLifecycle1() public t1 {
        option.mint(10);
        safeTransfer(address(option), address(0x123), 5);
        safeTransfer(address(redemption), address(0x123), 5);

        stableToken.mint(address(0x123), 1000e18);

        vm.startPrank(address(0x123));
        approve1(shakyToken_, address(factory));
        approve1(stableToken_, address(factory));
        option.exercise(3);
        redemption.redeemConsideration(2);
        vm.stopPrank();

        assertEq(option.balanceOf(address(0x123)), 2);
        assertEq(redemption.balanceOf(address(0x123)), 3);
    }

    function test_FullLifecycle2() public t1 {
        option.mint(10);
        safeTransfer(address(option), address(0x123), 5);

        vm.prank(address(0x123));
        safeTransfer(address(option), address(0x456), 3);

        option.redeem(5);

        assertEq(option.balanceOf(address(this)), 0);
        assertEq(redemption.balanceOf(address(this)), 5);
        assertEq(option.balanceOf(address(0x123)), 2);
        assertEq(option.balanceOf(address(0x456)), 3);
    }

    function test_PostExpirationFlow() public t1 {
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

    function test_ShortOptionSweepMultipleUsers() public t1 {
        option.mint(10);

        vm.warp(block.timestamp + 2 days);

        redemption.sweep(address(this));

        assertEq(redemption.balanceOf(address(this)), 0);
    }

    function test_DirectShortTransfer() public t1 {
        option.mint(10);
        safeTransfer(address(redemption), address(0x123), 5);

        assertEq(redemption.balanceOf(address(0x123)), 5);
        assertEq(redemption.balanceOf(address(this)), 5);
    }
}

contract OptionTestLimited is Test {
    using SafeERC20 for IERC20;

    StableToken public stableToken;
    ShakyToken public shakyToken;
    Redemption public redemptionClone;
    Option public optionClone;
    OptionFactory public factory;

    IPermit2 permit2 = IPermit2(PERMIT2);
    Option option;
    Redemption redemption;
    address shakyToken_;
    address stableToken_;
    address factory_;

    // Unichain RPC URL - replace with actual Unichain RPC endpoint
    string constant UNICHAIN_RPC_URL = "https://unichain.drpc.org";
    address constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;

    uint160 constant MAX160 = type(uint160).max;
    uint48 constant MAX48 = type(uint48).max;
    uint256 constant MAX256 = type(uint256).max;

    function setUp() public {
        // Fork Unichain at the latest block
        vm.createSelectFork(UNICHAIN_RPC_URL);

        // Deploy OptionFactory

        // OptionParameter[] memory options = new OptionParameter[](1);
        // options[0] = OptionParameter({
        //     longSymbol: "LONG",
        //     shortSymbol: "SHORT",
        //     collateral: address(weth),
        //     consideration: address(usdc),
        //     expiration: block.timestamp + 1 days,
        //     strike: 100,
        //     isPut: false
        // });

        // factory.createOptions(options);

        // OptionParameter[] memory options = new OptionParameter[](1);
        // options[0] = OptionParameter({
        //     optionSymbol: "LONG",
        //     redemptionSymbol: "SHORT",
        //     collateral_: address(shakyToken),
        //     consideration_: address(stableToken),
        //     expiration: block.timestamp + 1 days,
        //     strike: 1e18,
        //     isPut: false
        // });

        // factory.createOptions(options);

        // address[] memory options1 = factory.getOptions();
        // option = Option(options1[0]);

        // redemption = option.redemption();

        // approve1(shakyToken_, address(factory));
        // approve1(stableToken_, address(factory));
    }

    function approve1(address token, address spender) public {
        IERC20(token).approve(PERMIT2, MAX256);
        permit2.approve(token, spender, MAX160, MAX48);
    }

    function approve2(address token, address spender) public {
        IERC20(token).approve(spender, MAX256);
    }

    function safeTransfer(address token, address to, uint256 amount) internal {
        IERC20(token).safeTransfer(to, amount);
    }

    function safeTransferFrom(address token, address from, address to, uint256 amount) internal {
        IERC20(token).safeTransferFrom(from, to, amount);
    }

    function consoleBalances() public view {
        console.log("ShakyToken balance:", shakyToken.balanceOf(address(this)));
        console.log("StableToken balance:", stableToken.balanceOf(address(this)));
        console.log("LongOption balance:", option.balanceOf(address(this)));
        console.log("ShortOption balance:", redemption.balanceOf(address(this)));
    }

    modifier t1() {
        approve1(shakyToken_, address(factory));
        approve1(stableToken_, address(factory));
        _;
        consoleBalances();
    }

    modifier t2() {
        approve2(shakyToken_, address(factory));
        approve2(stableToken_, address(factory));
        _;
        consoleBalances();
    }

    function test_CreateOption() public {
        // Deploy tokens
        stableToken = new StableToken();
        shakyToken = new ShakyToken();
        shakyToken_ = address(shakyToken);
        stableToken_ = address(stableToken);

        // Mint tokens to test address
        stableToken.mint(address(this), 1_000_000 * 10 ** 18);
        shakyToken.mint(address(this), 1_000_000 * 10 ** 18);

        // Deploy ShortOption
        redemptionClone = new Redemption(
            "Short Option", "SHORT", address(stableToken), address(shakyToken), block.timestamp + 1 days, 100, false
        );

        // Deploy LongOption
        optionClone = new Option(
            "Long Option",
            "LONG",
            address(stableToken),
            address(shakyToken),
            block.timestamp + 1 days,
            100,
            false,
            address(redemptionClone)
        );
    }

    function test_CreateFactory() public {
        // Deploy tokens
        stableToken = new StableToken();
        shakyToken = new ShakyToken();
        shakyToken_ = address(shakyToken);
        stableToken_ = address(stableToken);

        // Mint tokens to test address
        stableToken.mint(address(this), 1_000_000 * 10 ** 18);
        shakyToken.mint(address(this), 1_000_000 * 10 ** 18);

        // Deploy ShortOption
        redemptionClone = new Redemption(
            "Short Option", "SHORT", address(stableToken), address(shakyToken), block.timestamp + 1 days, 100, false
        );

        // Deploy LongOption
        optionClone = new Option(
            "Long Option",
            "LONG",
            address(stableToken),
            address(shakyToken),
            block.timestamp + 1 days,
            100,
            false,
            address(redemptionClone)
        );

        factory = new OptionFactory(address(redemptionClone), address(optionClone), PERMIT2, 0.0001e18);
        factory_ = address(factory);
    }

    // function test_Transfer2() public t2 {
    //     safeTransfer(address(option), address(0x123), 1);
    // }

    // function test_TransferFrom1() public t1 {
    //     safeTransfer(address(option), address(0x123), 1);
    //     vm.prank(address(0x123));
    //     approve2(address(option), address(this));
    //     safeTransferFrom(address(option), address(0x123), address(this), 1);
    // }

    // function test_TransferTransfer() public t1 {
    //     safeTransfer(address(option), address(0x123), 1);
    //     vm.prank(address(0x123));
    //     safeTransfer(address(option), address(this), 1);
    // }

    // function test_Exercise1() public t1 {
    //     option.mint(1);
    //     option.exercise(1);
    // }

    // function test_Exercise2() public t2 {
    //     option.mint(1);
    //     option.exercise(1);
    // }

    // function test_Redeem1() public t1 {
    //     option.mint(1);
    //     option.redeem(1);
    // }

    // function test_Redeem2() public t2 {
    //     option.mint(1);
    //     option.redeem(1);
    // }

    // function test_RedeemConsideration1() public t1 {
    //     option.mint(1);
    //     option.exercise(1);
    //     redemption.redeemConsideration(1);
    // }

    // function test_RedeemConsideration2() public t2 {
    //     option.mint(1);
    //     option.exercise(1);
    //     redemption.redeemConsideration(1);
    // }

    // function test_ZeroAmountMint() public t1 {
    //     vm.expectRevert();
    //     option.mint(0);
    // }

    // function test_ZeroAmountExercise() public t1 {
    //     option.mint(1);
    //     vm.expectRevert();
    //     option.exercise(0);
    // }

    // function test_ZeroAmountRedeem() public t1 {
    //     option.mint(1);
    //     vm.expectRevert();
    //     option.redeem(0);
    // }

    // function test_InsufficientBalanceExercise() public t1 {
    //     option.mint(1);
    //     vm.expectRevert();
    //     option.exercise(2);
    // }

    // function test_InsufficientBalanceRedeem() public t1 {
    //     option.mint(1);
    //     vm.expectRevert();
    //     option.redeem(2);
    // }

    // function test_DoubleExercise() public t1 {
    //     option.mint(1);
    //     option.exercise(1);
    //     vm.expectRevert();
    //     option.exercise(1);
    // }

    // function test_ExerciseAfterExpiration() public t1 {
    //     option.mint(1);
    //     vm.warp(block.timestamp + 2 days);
    //     vm.expectRevert();
    //     option.exercise(1);
    // }

    // function test_MintAfterExpiration() public t1 {
    //     vm.warp(block.timestamp + 2 days);
    //     vm.expectRevert();
    //     option.mint(1);
    // }

    // function test_RedeemAfterExpiration() public t1 {
    //     option.mint(1);
    //     vm.warp(block.timestamp + 2 days);
    //     vm.expectRevert();
    //     option.redeem(1);
    // }

    // function test_ShortRedeemAfterExpiration() public t1 {
    //     option.mint(1);
    //     vm.warp(block.timestamp + 2 days);
    //     redemption.redeem(1);
    // }

    // function test_LockAndTransfer() public t1 {
    //     option.mint(1);
    //     option.lock();
    //     vm.expectRevert();
    //     IERC20(address(option)).transfer(address(0x123), 1);
    // }

    // function test_UnlockAndTransfer() public t1 {
    //     option.mint(1);
    //     option.lock();
    //     option.unlock();
    //     safeTransfer(address(option), address(0x123), 1);
    // }

    // function test_BalancesOf() public t1 {
    //     option.mint(1);
    //     Balances memory balances = option.balancesOf(address(this));
    //     assertEq(balances.option, 1);
    //     assertEq(balances.redemption, 1);
    //     assertGt(balances.collateral, 0);
    //     assertGt(balances.consideration, 0);
    // }

    // function test_Details() public view {
    //     option.details();
    // }

    // function test_CollateralData() public view {
    //     option.collateralData();
    // }

    // function test_ConsiderationData() public view {
    //     option.considerationData();
    // }

    // function test_RedeemWithAddress() public t1 {
    //     option.mint(1);
    //     option.redeem(address(this), 1);
    // }

    // function test_PartialExerciseAndRedeem() public t1 {
    //     option.mint(10);
    //     option.exercise(5);
    //     option.redeem(5);
    // }

    // function test_MultipleUsers() public t1 {
    //     option.mint(10);
    //     safeTransfer(address(option), address(0x123), 5);

    //     stableToken.mint(address(0x123), 1000e18);

    //     vm.startPrank(address(0x123));
    //     approve1(shakyToken_, address(factory));
    //     approve1(stableToken_, address(factory));
    //     option.exercise(3);
    //     vm.stopPrank();

    //     assertEq(option.balanceOf(address(0x123)), 2);
    // }

    // function test_TransferChain() public t1 {
    //     option.mint(10);
    //     safeTransfer(address(option), address(0x123), 5);

    //     vm.prank(address(0x123));
    //     safeTransfer(address(option), address(0x456), 3);

    //     vm.prank(address(0x456));
    //     safeTransfer(address(option), address(this), 2);

    //     assertEq(option.balanceOf(address(this)), 5);
    //     assertEq(option.balanceOf(address(0x123)), 2);
    //     assertEq(option.balanceOf(address(0x456)), 1);
    // }

    // function test_Sweep() public t1 {
    //     option.mint(5);
    //     vm.warp(block.timestamp + 2 days);
    //     redemption.sweep(address(this));
    //     assertEq(redemption.balanceOf(address(this)), 0);
    // }

    // function test_ToConsideration() public view {
    //     uint256 amount = 1e18;
    //     uint256 consAmount = option.toConsideration(amount);
    //     assertEq(consAmount, 1e18);
    // }

    // function test_ToCollateral() public view {
    //     uint256 consAmount = 1e18;
    //     uint256 amount = option.toCollateral(consAmount);
    //     assertEq(amount, 1e18);
    // }

    // function test_TransferAutoMint() public t1 {
    //     safeTransfer(address(option), address(0x123), 5);
    //     assertEq(option.balanceOf(address(0x123)), 5);
    //     assertEq(redemption.balanceOf(address(this)), 5);
    // }

    // function test_TransferFromAutoRedeem() public t1 {
    //     option.mint(10);
    //     safeTransfer(address(option), address(0x123), 5);

    //     vm.prank(address(0x123));
    //     approve2(address(option), address(this));

    //     uint256 shortBalanceBefore = redemption.balanceOf(address(this));
    //     safeTransferFrom(address(option), address(0x123), address(this), 3);
    //     uint256 shortBalanceAfter = redemption.balanceOf(address(this));

    //     assertEq(shortBalanceBefore - shortBalanceAfter, 3);
    // }

    // function test_ExerciseAllThenRedeem() public t1 {
    //     option.mint(5);
    //     option.exercise(5);
    //     vm.expectRevert();
    //     option.redeem(1);
    // }

    // function test_ShortRedeemWithMixedCollateral() public t1 {
    //     option.mint(10);
    //     option.exercise(6);

    //     vm.warp(block.timestamp + 2 days);
    //     redemption.redeem(10);
    // }

    // function test_RedeemConsiderationInsufficientBalance() public {
    //     approve1(shakyToken_, address(factory));
    //     approve1(stableToken_, address(factory));

    //     option.mint(10);

    //     vm.expectRevert(OptionBase.InsufficientConsideration.selector);
    //     redemption.redeemConsideration(10);
    // }

    // function test_MintToAddress() public {
    //     shakyToken.mint(address(0x123), 1000e18);

    //     vm.startPrank(address(0x123));
    //     approve1(shakyToken_, address(factory));
    //     option.mint(address(0x123), 5);
    //     vm.stopPrank();

    //     assertEq(option.balanceOf(address(0x123)), 5);
    //     assertEq(redemption.balanceOf(address(0x123)), 5);
    // }

    // function test_TransferBothTokensToSameAddress() public t1 {
    //     option.mint(10);

    //     uint256 longBefore = option.balanceOf(address(this));
    //     uint256 shortBefore = redemption.balanceOf(address(this));

    //     safeTransfer(address(option), address(0x123), 5);

    //     assertEq(longBefore, 10);
    //     assertEq(shortBefore, 10);
    //     assertEq(option.balanceOf(address(0x123)), 5);
    //     assertEq(option.balanceOf(address(this)), 5);
    //     assertEq(redemption.balanceOf(address(0x123)), 0);
    //     assertEq(redemption.balanceOf(address(this)), 10);
    // }

    // function test_MultipleExerciseSessions() public t1 {
    //     option.mint(10);
    //     option.exercise(2);
    //     option.exercise(3);
    //     option.exercise(1);

    //     assertEq(option.balanceOf(address(this)), 4);
    // }

    // function test_MultipleRedeemSessions() public t1 {
    //     option.mint(10);
    //     option.redeem(2);
    //     option.redeem(3);
    //     option.redeem(1);

    //     assertEq(option.balanceOf(address(this)), 4);
    //     assertEq(redemption.balanceOf(address(this)), 4);
    // }

    // function test_TransferFromWithApproval() public t1 {
    //     option.mint(10);
    //     option.approve(address(0x123), 5);

    //     vm.prank(address(0x123));
    //     safeTransferFrom(address(option), address(this), address(0x456), 3);

    //     assertEq(option.balanceOf(address(0x456)), 3);
    // }

    // function test_ExerciseWithInsufficientConsideration() public {
    //     approve1(shakyToken_, factory_);
    //     approve1(stableToken_, factory_);

    //     option.mint(100);

    //     uint256 stableBalance = stableToken.balanceOf(address(this));

    //     // stableToken.transfer(address(0x999), stableBalance);
    //     safeTransfer(stableToken_, address(0x999), stableBalance);

    //     vm.expectRevert();
    //     option.exercise(100);
    // }

    // function test_LockPreventsTransferFrom() public t1 {
    //     option.mint(10);
    //     safeTransfer(address(option), address(0x123), 5);

    //     vm.prank(address(0x123));
    //     approve2(address(option), address(this));

    //     option.lock();

    //     vm.expectRevert();
    //     IERC20(address(option)).transferFrom(address(0x123), address(this), 3);
    // }

    // function test_FullLifecycle1() public t1 {
    //     option.mint(10);
    //     safeTransfer(address(option), address(0x123), 5);
    //     safeTransfer(address(redemption), address(0x123), 5);

    //     stableToken.mint(address(0x123), 1000e18);

    //     vm.startPrank(address(0x123));
    //     approve1(shakyToken_, address(factory));
    //     approve1(stableToken_, address(factory));
    //     option.exercise(3);
    //     redemption.redeemConsideration(2);
    //     vm.stopPrank();

    //     assertEq(option.balanceOf(address(0x123)), 2);
    //     assertEq(redemption.balanceOf(address(0x123)), 3);
    // }

    // function test_FullLifecycle2() public t1 {
    //     option.mint(10);
    //     safeTransfer(address(option), address(0x123), 5);

    //     vm.prank(address(0x123));
    //     safeTransfer(address(option), address(0x456), 3);

    //     option.redeem(5);

    //     assertEq(option.balanceOf(address(this)), 0);
    //     assertEq(redemption.balanceOf(address(this)), 5);
    //     assertEq(option.balanceOf(address(0x123)), 2);
    //     assertEq(option.balanceOf(address(0x456)), 3);
    // }

    // function test_PostExpirationFlow() public t1 {
    //     option.mint(10);
    //     safeTransfer(address(redemption), address(0x123), 5);

    //     vm.warp(block.timestamp + 10 days);

    //     redemption.redeem(5);

    //     vm.prank(address(0x123));
    //     redemption.redeem(5);

    //     assertEq(redemption.balanceOf(address(this)), 0);
    //     assertEq(redemption.balanceOf(address(0x123)), 0);
    // }

    // function test_DecimalConversionRoundtrip() public view {
    //     uint256 amount = 12345e18;
    //     uint256 consAmount = option.toConsideration(amount);
    //     uint256 backToAmount = option.toCollateral(consAmount);
    //     assertEq(amount, backToAmount);
    // }

    // function test_ShortOptionSweepMultipleUsers() public t1 {
    //     option.mint(10);

    //     vm.warp(block.timestamp + 2 days);

    //     redemption.sweep(address(this));

    //     assertEq(redemption.balanceOf(address(this)), 0);
    // }

    // function test_DirectShortTransfer() public t1 {
    //     option.mint(10);
    //     safeTransfer(address(redemption), address(0x123), 5);

    //     assertEq(redemption.balanceOf(address(0x123)), 5);
    //     assertEq(redemption.balanceOf(address(this)), 5);
    // }
}
