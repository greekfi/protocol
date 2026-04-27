// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { Test, console } from "forge-std/Test.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { Factory } from "../contracts/Factory.sol";
import { Collateral } from "../contracts/Collateral.sol";
import { Option } from "../contracts/Option.sol";
import { CreateParams } from "../contracts/interfaces/IFactory.sol";
import { ISettlementSwapper } from "../contracts/interfaces/ISettlementSwapper.sol";
import { MockPriceOracle } from "./mocks/MockPriceOracle.sol";
import { MockERC20 } from "../contracts/mocks/MockERC20.sol";

/// @notice Deterministic swapper for unit tests. Converts `tokenIn` to `tokenOut` at a fixed
///         `rateWad` (18-dec fixed point, `consideration per collateral`). Mints `tokenOut`
///         directly to `recipient` — works only against {MockERC20} which exposes `mint`.
contract MockSwapper is ISettlementSwapper {
    uint256 public rateWad;
    uint8 public collDecimals;
    uint8 public consDecimals;

    constructor(uint256 rateWad_, uint8 collDecimals_, uint8 consDecimals_) {
        rateWad = rateWad_;
        collDecimals = collDecimals_;
        consDecimals = consDecimals_;
    }

    function swap(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minOut,
        address recipient,
        bytes calldata /* routeHint */
    ) external returns (uint256 amountOut) {
        IERC20(tokenIn).transferFrom(msg.sender, address(this), amountIn);
        amountOut = (amountIn * rateWad * (10 ** consDecimals)) / (1e18 * (10 ** collDecimals));
        require(amountOut >= minOut, "slip");
        MockERC20(tokenOut).mint(recipient, amountOut);
    }
}

contract CashSettlementTest is Test {
    MockERC20 public weth;
    MockERC20 public usdc;
    Collateral public collTpl;
    Option public optTpl;
    Factory public factory;
    MockPriceOracle public oracle;
    Option public opt;
    Collateral public coll;

    uint256 constant STRIKE_WAD = 2000e18;
    uint256 constant SPOT_WAD = 3000e18;

    address public alice = address(0xA11CE);
    address public bob = address(0xB0B);
    address public carol = address(0xCA401);
    address public keeper = address(0xDEAD);

    uint40 public expiration;

    function setUp() public {
        weth = new MockERC20("Wrapped Ether", "WETH", 18);
        usdc = new MockERC20("USD Coin", "USDC", 6);

        collTpl = new Collateral("Short", "S");
        optTpl = new Option("Long", "L");
        factory = new Factory(address(collTpl), address(optTpl));

        expiration = uint40(block.timestamp + 7 days);
        oracle = new MockPriceOracle(expiration);
        oracle.setPrice(SPOT_WAD);

        CreateParams memory p = CreateParams({
            collateral: address(weth),
            consideration: address(usdc),
            expirationDate: expiration,
            strike: uint96(STRIKE_WAD),
            isPut: false,
            isEuro: false,
            oracleSource: address(oracle),
            twapWindow: 0
        });
        opt = Option(factory.createOption(p));
        coll = Collateral(opt.coll());

        _mintOptionTo(alice, 1 ether);
        _mintOptionTo(bob, 1 ether);
        _mintOptionTo(carol, 1 ether);
    }

    function _mintOptionTo(address to, uint256 amount) internal {
        weth.mint(address(this), amount);
        weth.approve(address(factory), type(uint256).max);
        factory.approve(address(weth), uint160(amount));
        opt.mint(amount);
        opt.transfer(to, amount);
    }

    function _residualPerOption() internal pure returns (uint256) {
        return (SPOT_WAD - STRIKE_WAD) * 1e18 / SPOT_WAD;
    }

    function _expectedCashPerOption() internal pure returns (uint256) {
        // USDC paid per option unit = residualWETH × spot / 1e18, scaled for 6-dec USDC.
        uint256 residualWad = _residualPerOption(); // 1e18-scaled factor
        return residualWad * SPOT_WAD * 1e6 / (1e18 * 1e18);
    }

    // ============ CLAIM API ============

    function test_claim_defaultIsCash_allHolders() public {
        // Nobody opts out — everyone gets cash.
        vm.warp(expiration + 1);
        MockSwapper swapper = new MockSwapper(SPOT_WAD, 18, 6);
        coll.convertResidualToConsideration(swapper, 0, "");

        uint256 expected = _expectedCashPerOption();

        vm.prank(alice); opt.claim(1 ether);
        vm.prank(bob);   opt.claim(1 ether);
        vm.prank(carol); opt.claim(1 ether);

        assertApproxEqAbs(usdc.balanceOf(alice), expected, 1);
        assertApproxEqAbs(usdc.balanceOf(bob), expected, 1);
        assertApproxEqAbs(usdc.balanceOf(carol), expected, 1);
        assertEq(weth.balanceOf(alice), 0);
    }

    function test_claim_partialOptInCollateral() public {
        // carol wants in-kind collateral; alice and bob stay default cash.
        vm.warp(expiration + 1);
        vm.prank(carol); coll.requestCollateral();
        assertTrue(coll.wantsCollateral(carol));
        assertEq(coll.collateralLockedOf(carol), 1 ether);
        assertEq(coll.totalCollateralReservedOptions(), 1 ether);

        MockSwapper swapper = new MockSwapper(SPOT_WAD, 18, 6);
        coll.convertResidualToConsideration(swapper, 0, "");

        vm.prank(alice); opt.claim(1 ether);
        vm.prank(bob);   opt.claim(1 ether);
        vm.prank(carol); opt.claim(1 ether);

        // alice/bob got USDC
        uint256 expectedCash = _expectedCashPerOption();
        assertApproxEqAbs(usdc.balanceOf(alice), expectedCash, 1);
        assertApproxEqAbs(usdc.balanceOf(bob), expectedCash, 1);
        assertEq(usdc.balanceOf(carol), 0);

        // carol got WETH
        uint256 expectedCollateral = 1 ether * _residualPerOption() / 1e18;
        assertApproxEqAbs(weth.balanceOf(carol), expectedCollateral, 1);
    }

    function test_claim_noArgsMaxesBalance() public {
        vm.warp(expiration + 1);
        MockSwapper swapper = new MockSwapper(SPOT_WAD, 18, 6);
        coll.convertResidualToConsideration(swapper, 0, "");

        vm.prank(alice);
        opt.claim(); // no args → max alice's balance
        assertEq(opt.balanceOf(alice), 0);
        assertGt(usdc.balanceOf(alice), 0);
    }

    function test_claim_permissionlessHolder() public {
        vm.warp(expiration + 1);
        MockSwapper swapper = new MockSwapper(SPOT_WAD, 18, 6);
        coll.convertResidualToConsideration(swapper, 0, "");

        // keeper triggers claim on alice's behalf — payout goes to alice, keeper just paid gas.
        vm.prank(keeper);
        opt.claim(alice);
        assertEq(opt.balanceOf(alice), 0);
        assertGt(usdc.balanceOf(alice), 0);
        assertEq(usdc.balanceOf(keeper), 0);
    }

    function test_claim_permissionlessHolderAmount() public {
        vm.warp(expiration + 1);
        MockSwapper swapper = new MockSwapper(SPOT_WAD, 18, 6);
        coll.convertResidualToConsideration(swapper, 0, "");

        // keeper claims partial amount for bob.
        vm.prank(keeper);
        opt.claim(bob, 0.4 ether);
        assertEq(opt.balanceOf(bob), 0.6 ether);
        assertGt(usdc.balanceOf(bob), 0);
    }

    function test_claim_permissionlessHolder_noBalance_noOp() public {
        vm.warp(expiration + 1);
        MockSwapper swapper = new MockSwapper(SPOT_WAD, 18, 6);
        coll.convertResidualToConsideration(swapper, 0, "");

        // Trigger claim for an address that never held any options — should silently no-op.
        vm.prank(keeper);
        opt.claim(address(0xFACE));
    }

    // ============ FLAG TOGGLE ============

    function test_requestCollateral_and_requestConsideration() public {
        vm.warp(expiration + 1);

        vm.prank(alice);
        coll.requestCollateral();
        assertTrue(coll.wantsCollateral(alice));
        assertEq(coll.collateralLockedOf(alice), 1 ether);
        assertEq(coll.totalCollateralReservedOptions(), 1 ether);

        vm.prank(alice);
        coll.requestConsideration(); // flip back to default
        assertFalse(coll.wantsCollateral(alice));
        assertEq(coll.collateralLockedOf(alice), 0);
        assertEq(coll.totalCollateralReservedOptions(), 0);

        vm.prank(alice);
        coll.requestCollateral();
        assertEq(coll.collateralLockedOf(alice), 1 ether);
    }

    function test_flagFlip_blockedAfterSwap() public {
        vm.warp(expiration + 1);
        MockSwapper swapper = new MockSwapper(SPOT_WAD, 18, 6);
        coll.convertResidualToConsideration(swapper, 0, "");

        vm.expectRevert();
        vm.prank(alice);
        coll.requestCollateral();
    }

    // ============ MIXED PRE/POST SWAP ============

    function test_preSwap_claimSilentlyFallsBackInKind() public {
        // Default is cash but swap hasn't run → claim must still succeed, paying in-kind WETH.
        vm.warp(expiration + 1);
        vm.prank(alice);
        opt.claim(1 ether);
        assertGt(weth.balanceOf(alice), 0);
        assertEq(usdc.balanceOf(alice), 0);
    }

    function test_swap_idempotent() public {
        vm.warp(expiration + 1);
        MockSwapper swapper = new MockSwapper(SPOT_WAD, 18, 6);
        coll.convertResidualToConsideration(swapper, 0, "");
        vm.expectRevert();
        coll.convertResidualToConsideration(swapper, 0, "");
    }

    // ============ SHORT SIDE (unaffected) ============

    function test_shortSide_inKindClaimsAndRedeemsStillWork() public {
        // Short holder (the test contract, from minting) redeems as normal.
        // We also include an in-kind carol to ensure reserve math holds after swap.
        vm.warp(expiration + 1);
        vm.prank(carol); coll.requestCollateral();
        MockSwapper swapper = new MockSwapper(SPOT_WAD, 18, 6);
        coll.convertResidualToConsideration(swapper, 0, "");

        vm.prank(alice); opt.claim(1 ether); // cash
        vm.prank(carol); opt.claim(1 ether); // collateral

        // Short side redeems whatever's left pro-rata.
        coll.redeem();
        assertGt(weth.balanceOf(address(this)), 0);
    }
}
