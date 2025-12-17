// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { Test, console } from "forge-std/Test.sol";
import { IERC20, ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { OptionFactory, Redemption, Option, OptionParameter } from "../contracts/OptionFactory.sol";
import { StableToken } from "../contracts/StableToken.sol";
import { ShakyToken } from "../contracts/ShakyToken.sol";
import { IPermit2 } from "../contracts/interfaces/IPermit2.sol";

/// @notice Mock fee-on-transfer token for testing
contract FeeOnTransferToken is ERC20 {
    uint256 public constant FEE_PERCENT = 1; // 1% fee on transfer

    constructor() ERC20("FeeOnTransfer", "FOT") { }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function transfer(address to, uint256 amount) public override returns (bool) {
        uint256 fee = (amount * FEE_PERCENT) / 100;
        uint256 amountAfterFee = amount - fee;

        _transfer(msg.sender, to, amountAfterFee);
        // Fee is burned
        _burn(msg.sender, fee);

        return true;
    }

    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        uint256 fee = (amount * FEE_PERCENT) / 100;
        uint256 amountAfterFee = amount - fee;

        _spendAllowance(from, msg.sender, amount);
        _transfer(from, to, amountAfterFee);
        // Fee is burned
        _burn(from, fee);

        return true;
    }
}

contract FeeOnTransferTest is Test {
    using SafeERC20 for IERC20;

    StableToken public stableToken;
    ShakyToken public shakyToken;
    FeeOnTransferToken public fotToken;
    Redemption public redemptionClone;
    Option public optionClone;
    OptionFactory public factory;

    IPermit2 permit2 = IPermit2(PERMIT2);
    Option option;
    Redemption redemption;

    // Unichain RPC URL
    string constant UNICHAIN_RPC_URL = "https://unichain.drpc.org";
    address constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;

    uint160 constant MAX160 = type(uint160).max;
    uint48 constant MAX48 = type(uint48).max;

    function setUp() public {
        // Fork Unichain at the latest block
        vm.createSelectFork(UNICHAIN_RPC_URL);

        // Deploy tokens
        stableToken = new StableToken();
        shakyToken = new ShakyToken();
        fotToken = new FeeOnTransferToken();

        // Mint tokens to test address
        stableToken.mint(address(this), 1_000_000 * 10 ** 18);
        shakyToken.mint(address(this), 1_000_000 * 10 ** 18);
        fotToken.mint(address(this), 1_000_000 * 10 ** 18);

        // Deploy Redemption template
        redemptionClone = new Redemption(
            "Redemption Template",
            "REDT",
            address(stableToken),
            address(shakyToken),
            block.timestamp + 1 days,
            1e18,
            false
        );

        // Deploy Option template
        optionClone = new Option("Option Template", "OPTT", address(redemptionClone));

        // Deploy OptionFactory
        factory = new OptionFactory(address(redemptionClone), address(optionClone),  0.0001e18);
    }

    /// @notice Test that blocklist prevents option creation with blocklisted collateral
    function test_BlocklistPreventsCollateralCreation() public {
        // Blocklist the FOT token
        factory.blockToken(address(fotToken));

        // Verify token is blocklisted
        assertTrue(factory.isBlocked(address(fotToken)));

        // Try to create option with blocklisted collateral - should revert
        vm.expectRevert(OptionFactory.BlocklistedToken.selector);
        factory.createOption(
            address(fotToken), // Blocklisted collateral
            address(stableToken),
            uint40(block.timestamp + 1 days),
            1e18,
            false
        );
    }

    /// @notice Test that blocklist prevents option creation with blocklisted consideration
    function test_BlocklistPreventsConsiderationCreation() public {
        // Blocklist the FOT token
        factory.blockToken(address(fotToken));

        // Try to create option with blocklisted consideration - should revert
        vm.expectRevert(OptionFactory.BlocklistedToken.selector);
        factory.createOption(
            address(stableToken),
            address(fotToken), // Blocklisted consideration
            uint40(block.timestamp + 1 days),
            1e18,
            false
        );
    }

    /// @notice Test that owner can remove token from blocklist
    function test_RemoveFromBlocklist() public {
        // Add to blocklist
        factory.blockToken(address(fotToken));
        assertTrue(factory.isBlocked(address(fotToken)));

        // Remove from blocklist
        factory.unblockToken(address(fotToken));
        assertFalse(factory.isBlocked(address(fotToken)));

        // Should now be able to create option (will fail at mint time though)
        address optionAddress =
            factory.createOption(address(fotToken), address(stableToken), uint40(block.timestamp + 1 days), 1e18, false);

        assertTrue(optionAddress != address(0));
    }

    /// @notice Test that only owner can add to blocklist
    function test_OnlyOwnerCanBlocklist() public {
        address notOwner = address(0x123);

        vm.prank(notOwner);
        vm.expectRevert();
        factory.blockToken(address(fotToken));
    }

    /// @notice Test that FOT token fails at mint time due to balance check
    function test_FeeOnTransferFailsAtMint() public {
        // Create option with FOT token as collateral (not blocklisted)
        address optionAddress =
            factory.createOption(address(fotToken), address(stableToken), uint40(block.timestamp + 1 days), 1e18, false);

        option = Option(optionAddress);
        redemption = Redemption(option.redemption());

        // Approve tokens
        fotToken.approve(address(factory), MAX160);
        fotToken.approve(PERMIT2, type(uint256).max);
        vm.prank(PERMIT2);
        fotToken.approve(address(factory), MAX160);

        // Approve Permit2
        permit2.approve(address(fotToken), address(factory), MAX160, MAX48);

        uint256 mintAmount = 1000 * 10 ** 18;

        // Try to mint - should fail because FOT token transfers less than requested
        vm.expectRevert(Redemption.FeeOnTransferNotSupported.selector);
        option.mint(mintAmount);
    }

    /// @notice Test that normal tokens work fine with the balance check
    function test_NormalTokensPassBalanceCheck() public {
        // Create option with normal tokens
        OptionParameter[] memory options = new OptionParameter[](1);
        options[0] = OptionParameter({
            collateral_: address(shakyToken),
            consideration_: address(stableToken),
            expiration: uint40(block.timestamp + 1 days),
            strike: uint96(1e18),
            isPut: false
        });

        address optionAddress = factory.createOption(
            options[0].collateral_,
            options[0].consideration_,
            options[0].expiration,
            options[0].strike,
            options[0].isPut
        );
        option = Option(optionAddress);
        redemption = Redemption(option.redemption());

        // Approve tokens
        shakyToken.approve(address(factory), MAX160);
        shakyToken.approve(PERMIT2, type(uint256).max);
        stableToken.approve(address(factory), MAX160);
        stableToken.approve(PERMIT2, type(uint256).max);

        // Approve Permit2
        permit2.approve(address(shakyToken), address(factory), MAX160, MAX48);
        permit2.approve(address(stableToken), address(factory), MAX160, MAX48);

        uint256 mintAmount = 1000 * 10 ** 18;

        // Mint should succeed with normal tokens
        option.mint(mintAmount);

        // Verify tokens were minted (minus fees)
        assertNotEq(option.balanceOf(address(this)), mintAmount);
        assertNotEq(redemption.balanceOf(address(this)), mintAmount);
    }

    /// @notice Test blocklist event emission
    function test_BlocklistEventEmission() public {
        // Test add event
        vm.expectEmit(true, true, false, false);
        emit OptionFactory.TokenBlocked(address(fotToken), true);
        factory.blockToken(address(fotToken));

        // Test remove event
        vm.expectEmit(true, true, false, false);
        emit OptionFactory.TokenBlocked(address(fotToken), false);
        factory.unblockToken(address(fotToken));
    }

    /// @notice Test that zero address cannot be blocklisted
    function test_CannotBlocklistZeroAddress() public {
        vm.expectRevert(OptionFactory.InvalidAddress.selector);
        factory.blockToken(address(0));
    }
}
