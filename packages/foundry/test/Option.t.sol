// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test, console} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {OptionFactory, ShortOption, LongOption, OptionParameter} from "../contracts/OptionFactory.sol";
import {StableToken} from "../contracts/StableToken.sol";
import {ShakyToken} from "../contracts/ShakyToken.sol";
import {IPermit2} from "../contracts/interfaces/IPermit2.sol";

contract OptionTest is Test {
    using SafeERC20 for IERC20;
    StableToken public stableToken;
    ShakyToken public shakyToken;
    ShortOption public short;
    LongOption public long;
    OptionFactory public factory;

    IPermit2 permit2 = IPermit2(PERMIT2);
    LongOption longOption;
    ShortOption shortOption_;
    address shortOption;
    address shakyToken_;
    address stableToken_;

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
        stableToken.mint(address(this), 1_000_000 * 10**18);
        shakyToken.mint(address(this), 1_000_000 * 10**18);

        // Deploy ShortOption
        short = new ShortOption(
            "Short Option",
            "SHORT",
            address(stableToken),
            address(shakyToken),
            block.timestamp + 1 days,
            100,
            false
        );

        // Deploy LongOption
        long = new LongOption(
            "Long Option",
            "LONG",
            address(stableToken),
            address(shakyToken),
            block.timestamp + 1 days,
            100,
            false,
            address(short)
        );

        // Deploy OptionFactory
        factory = new OptionFactory(address(short), address(long));

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
            longSymbol: "LONG",
            shortSymbol: "SHORT",
            collateral: address(shakyToken),
            consideration: address(stableToken),
            expiration: block.timestamp + 1 days,
            strike: 1e18,
            isPut: false
        });

        factory.createOptions(options);


        address[] memory options1 = factory.getCreatedOptions();
        longOption = LongOption(options1[0]);
        shortOption = longOption.shortOption();

        shortOption_ = longOption.short();
    }

    function approve1(address token, address spender) public {
        IERC20(token).approve(PERMIT2, MAX256);
        permit2.approve(token, spender, MAX160, MAX48);
    }

    function approve2(address token, address spender) public {
        IERC20(token).approve(spender, MAX256);
    }

    function safeTransfer(address token, address to, uint256 amount) internal {
        require(IERC20(token).transfer(to, amount), "Transfer failed");
    }

    function safeTransferFrom(address token, address from, address to, uint256 amount) internal {
        require(IERC20(token).transferFrom(from, to, amount), "TransferFrom failed");
    }

    function consoleBalances() public view {
        console.log("ShakyToken balance:", shakyToken.balanceOf(address(this)));
        console.log("StableToken balance:", stableToken.balanceOf(address(this)));
        console.log("LongOption balance:", longOption.balanceOf(address(this)));
        console.log("ShortOption balance:", shortOption_.balanceOf(address(this)));
    }

    modifier t1 {
        approve1(shakyToken_, shortOption);
        approve1(stableToken_, shortOption);
        _;
        consoleBalances();
    }

    modifier t2 {
        approve2(shakyToken_, shortOption);
        approve2(stableToken_, shortOption);
        _;
        consoleBalances();
    }

    function test_Mint() public t1 {
        longOption.mint(1);
    }

    function test_Transfer1() public t1 {
        longOption.mint(1);
        safeTransfer(address(longOption), address(0x123), 1);
    }

    function test_Transfer2() public t2 {
        longOption.mint(1);
        safeTransfer(address(longOption), address(0x123), 1);
    }

    function test_TransferFrom1() public t1 {
        safeTransfer(address(longOption), address(0x123), 1);
        vm.prank(address(0x123));
        approve2(address(longOption), address(this));
        safeTransferFrom(address(longOption), address(0x123), address(this), 1);
    }

    function test_TransferTransfer() public t1 {
        safeTransfer(address(longOption), address(0x123), 1);
        vm.prank(address(0x123));
        safeTransfer(address(longOption), address(this), 1);
        }

    function test_Exercise1() public t1 {
        longOption.mint(1);
        longOption.exercise(1);
    }

    function test_Exercise2() public t2 {
        longOption.mint(1);
        longOption.exercise(1);
    }

    function test_Redeem1() public t1 {
        longOption.mint(1);
        longOption.redeem(1);
    }

    function test_Redeem2() public t2 {
        longOption.mint(1);
        longOption.redeem(1);
    }

    function test_RedeemConsideration1() public t1 {
        longOption.mint(1);
        longOption.exercise(1);
        shortOption_.redeemConsideration(1);
    }

    function test_RedeemConsideration2() public t2 {
        longOption.mint(1);
        longOption.exercise(1);
        shortOption_.redeemConsideration(1);
    }

    function test_ZeroAmountMint() public t1 {
        vm.expectRevert();
        longOption.mint(0);
    }

    function test_ZeroAmountExercise() public t1 {
        longOption.mint(1);
        vm.expectRevert();
        longOption.exercise(0);
    }

    function test_ZeroAmountRedeem() public t1 {
        longOption.mint(1);
        vm.expectRevert();
        longOption.redeem(0);
    }

    function test_InsufficientBalanceExercise() public t1 {
        longOption.mint(1);
        vm.expectRevert();
        longOption.exercise(2);
    }

    function test_InsufficientBalanceRedeem() public t1 {
        longOption.mint(1);
        vm.expectRevert();
        longOption.redeem(2);
    }

    function test_DoubleExercise() public t1 {
        longOption.mint(1);
        longOption.exercise(1);
        vm.expectRevert();
        longOption.exercise(1);
    }

    function test_ExerciseAfterExpiration() public t1 {
        longOption.mint(1);
        vm.warp(block.timestamp + 2 days);
        vm.expectRevert();
        longOption.exercise(1);
    }

    function test_MintAfterExpiration() public t1 {
        vm.warp(block.timestamp + 2 days);
        vm.expectRevert();
        longOption.mint(1);
    }

    function test_RedeemAfterExpiration() public t1 {
        longOption.mint(1);
        vm.warp(block.timestamp + 2 days);
        vm.expectRevert();
        longOption.redeem(1);
    }

    function test_ShortRedeemAfterExpiration() public t1 {
        longOption.mint(1);
        vm.warp(block.timestamp + 2 days);
        shortOption_.redeem(1);
    }

    function test_LockAndTransfer() public t1 {
        longOption.mint(1);
        longOption.lock();
        vm.expectRevert();
        IERC20(address(longOption)).transfer(address(0x123), 1);
    }

    function test_UnlockAndTransfer() public t1 {
        longOption.mint(1);
        longOption.lock();
        longOption.unlock();
        safeTransfer(address(longOption), address(0x123), 1);
    }

    function test_BalancesOf() public t1 {
        longOption.mint(1);
        (uint256 collBalance, uint256 consBalance, uint256 longBalance, uint256 shortBalance) = longOption.balancesOf(address(this));
        assertEq(longBalance, 1);
        assertEq(shortBalance, 1);
        assertGt(collBalance, 0);
        assertGt(consBalance, 0);
    }

    function test_Details() public view {
        longOption.details();
    }

    function test_CollateralData() public view {
        longOption.collateralData();
    }

    function test_ConsiderationData() public view {
        longOption.considerationData();
    }

    function test_RedeemWithAddress() public t1 {
        longOption.mint(1);
        longOption.redeem(address(this), 1);
    }

    function test_PartialExerciseAndRedeem() public t1 {
        longOption.mint(10);
        longOption.exercise(5);
        longOption.redeem(5);
    }

    function test_MultipleUsers() public t1 {
        longOption.mint(10);
        safeTransfer(address(longOption), address(0x123), 5);

        stableToken.mint(address(0x123), 1000e18);

        vm.startPrank(address(0x123));
        approve1(shakyToken_, shortOption);
        approve1(stableToken_, shortOption);
        longOption.exercise(3);
        vm.stopPrank();

        assertEq(longOption.balanceOf(address(0x123)), 2);
    }

    function test_TransferChain() public t1 {
        longOption.mint(10);
        safeTransfer(address(longOption), address(0x123), 5);

        vm.prank(address(0x123));
        safeTransfer(address(longOption), address(0x456), 3);

        vm.prank(address(0x456));
        safeTransfer(address(longOption), address(this), 2);

        assertEq(longOption.balanceOf(address(this)), 5);
        assertEq(longOption.balanceOf(address(0x123)), 2);
        assertEq(longOption.balanceOf(address(0x456)), 1);
    }

    function test_Sweep() public t1 {
        longOption.mint(5);
        vm.warp(block.timestamp + 2 days);
        shortOption_.sweep(address(this));
        assertEq(shortOption_.balanceOf(address(this)), 0);
    }

    function test_ToConsideration() public view {
        uint256 amount = 1e18;
        uint256 consAmount = longOption.toConsideration(amount);
        assertEq(consAmount, 1e18);
    }

    function test_ToCollateral() public view {
        uint256 consAmount = 1e18;
        uint256 amount = longOption.toCollateral(consAmount);
        assertEq(amount, 1e18);
    }

    function test_TransferAutoMint() public t1 {
        // Mint first since auto-mint was removed for security
        longOption.mint(5);
        safeTransfer(address(longOption), address(0x123), 5);
        assertEq(longOption.balanceOf(address(0x123)), 5);
        assertEq(shortOption_.balanceOf(address(this)), 5);
    }

    function test_TransferFromAutoRedeem() public t1 {
        longOption.mint(10);
        safeTransfer(address(longOption), address(0x123), 5);

        vm.prank(address(0x123));
        approve2(address(longOption), address(this));

        uint256 shortBalanceBefore = shortOption_.balanceOf(address(this));
        safeTransferFrom(address(longOption), address(0x123), address(this), 3);
        uint256 shortBalanceAfter = shortOption_.balanceOf(address(this));

        assertEq(shortBalanceBefore - shortBalanceAfter, 3);
    }

    function test_ExerciseAllThenRedeem() public t1 {
        longOption.mint(5);
        longOption.exercise(5);
        vm.expectRevert();
        longOption.redeem(1);
    }

    function test_ShortRedeemWithMixedCollateral() public t1 {
        longOption.mint(10);
        longOption.exercise(6);

        vm.warp(block.timestamp + 2 days);
        shortOption_.redeem(10);
    }

    function test_RedeemConsiderationInsufficientBalance() public {
        approve1(shakyToken_, shortOption);
        approve1(stableToken_, shortOption);

        longOption.mint(10);

        vm.expectRevert(bytes("Insufficient Consideration"));
        shortOption_.redeemConsideration(10);
    }

    function test_MintToAddress() public {
        shakyToken.mint(address(0x123), 1000e18);

        vm.startPrank(address(0x123));
        approve1(shakyToken_, shortOption);
        longOption.mint(address(0x123), 5);
        vm.stopPrank();

        assertEq(longOption.balanceOf(address(0x123)), 5);
        assertEq(shortOption_.balanceOf(address(0x123)), 5);
    }

    function test_TransferBothTokensToSameAddress() public t1 {
        longOption.mint(10);

        uint256 longBefore = longOption.balanceOf(address(this));
        uint256 shortBefore = shortOption_.balanceOf(address(this));

        safeTransfer(address(longOption), address(0x123), 5);

        assertEq(longBefore, 10);
        assertEq(shortBefore, 10);
        assertEq(longOption.balanceOf(address(0x123)), 5);
        assertEq(longOption.balanceOf(address(this)), 5);
        assertEq(shortOption_.balanceOf(address(0x123)), 0);
        assertEq(shortOption_.balanceOf(address(this)), 10);
    }

    function test_MultipleExerciseSessions() public t1 {
        longOption.mint(10);
        longOption.exercise(2);
        longOption.exercise(3);
        longOption.exercise(1);

        assertEq(longOption.balanceOf(address(this)), 4);
    }

    function test_MultipleRedeemSessions() public t1 {
        longOption.mint(10);
        longOption.redeem(2);
        longOption.redeem(3);
        longOption.redeem(1);

        assertEq(longOption.balanceOf(address(this)), 4);
        assertEq(shortOption_.balanceOf(address(this)), 4);
    }

    function test_TransferFromWithApproval() public t1 {
        longOption.mint(10);
        longOption.approve(address(0x123), 5);

        vm.prank(address(0x123));
        safeTransferFrom(address(longOption), address(this), address(0x456), 3);

        assertEq(longOption.balanceOf(address(0x456)), 3);
    }

    function test_ExerciseWithInsufficientConsideration() public {
        approve1(shakyToken_, shortOption);
        approve1(stableToken_, shortOption);

        longOption.mint(100);

        uint256 stableBalance = stableToken.balanceOf(address(this));
        
        // stableToken.transfer(address(0x999), stableBalance);
        safeTransfer(stableToken_, address(0x999), stableBalance);

        vm.expectRevert();
        longOption.exercise(100);
    }

    function test_LockPreventsTransferFrom() public t1 {
        longOption.mint(10);
        safeTransfer(address(longOption), address(0x123), 5);

        vm.prank(address(0x123));
        approve2(address(longOption), address(this));

        longOption.lock();

        vm.expectRevert();
        IERC20(address(longOption)).transferFrom(address(0x123), address(this), 3);
    }

    function test_FullLifecycle1() public t1 {
        longOption.mint(10);
        safeTransfer(address(longOption), address(0x123), 5);
        safeTransfer(address(shortOption_), address(0x123), 5);

        stableToken.mint(address(0x123), 1000e18);

        vm.startPrank(address(0x123));
        approve1(shakyToken_, shortOption);
        approve1(stableToken_, shortOption);
        longOption.exercise(3);
        shortOption_.redeemConsideration(2);
        vm.stopPrank();

        assertEq(longOption.balanceOf(address(0x123)), 2);
        assertEq(shortOption_.balanceOf(address(0x123)), 3);
    }

    function test_FullLifecycle2() public t1 {
        longOption.mint(10);
        safeTransfer(address(longOption), address(0x123), 5);

        vm.prank(address(0x123));
        safeTransfer(address(longOption), address(0x456), 3);

        longOption.redeem(5);

        assertEq(longOption.balanceOf(address(this)), 0);
        assertEq(shortOption_.balanceOf(address(this)), 5);
        assertEq(longOption.balanceOf(address(0x123)), 2);
        assertEq(longOption.balanceOf(address(0x456)), 3);
    }

    function test_PostExpirationFlow() public t1 {
        longOption.mint(10);
        safeTransfer(address(shortOption_), address(0x123), 5);

        vm.warp(block.timestamp + 10 days);

        shortOption_.redeem(5);

        vm.prank(address(0x123));
        shortOption_.redeem(5);

        assertEq(shortOption_.balanceOf(address(this)), 0);
        assertEq(shortOption_.balanceOf(address(0x123)), 0);
    }

    function test_DecimalConversionRoundtrip() public view {
        uint256 amount = 12345e18;
        uint256 consAmount = longOption.toConsideration(amount);
        uint256 backToAmount = longOption.toCollateral(consAmount);
        assertEq(amount, backToAmount);
    }

    function test_ShortOptionSweepMultipleUsers() public t1 {
        longOption.mint(10);

        vm.warp(block.timestamp + 2 days);

        shortOption_.sweep(address(this));

        assertEq(shortOption_.balanceOf(address(this)), 0);
    }

    function test_DirectShortTransfer() public t1 {
        longOption.mint(10);
        safeTransfer(address(shortOption_), address(0x123), 5);

        assertEq(shortOption_.balanceOf(address(0x123)), 5);
        assertEq(shortOption_.balanceOf(address(this)), 5);
    }

}