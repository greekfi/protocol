// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { IPermit2 } from "./interfaces/IPermit2.sol";
import { OptionBase } from "./OptionBase.sol";

using SafeERC20 for IERC20;
// The Long Option contract is the owner of the Short Option contract
// The Long Option contract is the only one that can mint new mint
// The Long Option contract is the only one that can exercise mint
// The redemption is only possible if you own both the Long and Short Option contracts but
// performed by the Long Option contract

// In mint traditionally a Consideration is cash and a Collateral is an asset
// Here, we do not distinguish between the Cash and Asset concept and allow consideration
// to be any asset and collateral to be any asset as well. This can allow wETH to be used
// as collateral and wBTC to be used as consideration. Similarly, staked ETH can be used
// or even staked stable coins can be used as well for either consideration or collateral.

contract ShortOption is OptionBase {
    address public longOption;

    event Redemption(address longOption, address holder, uint256 amount);

    modifier sufficientCollateral(address owner, uint256 amount) {
        if (collateral.balanceOf(owner) < amount) {
            revert InsufficientBalance();
        }
        _;
    }

    constructor(
        string memory name,
        string memory symbol,
        address collateral,
        address consideration,
        uint256 expirationDate,
        uint256 strike,
        bool isPut
    ) OptionBase(name, symbol, collateral, consideration, expirationDate, strike, isPut) { }

    function setLongOption(address longOption_) public onlyOwner {
        longOption = longOption_;
    }

    function mint(IPermit2.PermitTransferFrom calldata permit, IPermit2.SignatureTransferDetails calldata transferDetails, address owner, bytes calldata signature)
        public
        onlyOwner
        validAmount(transferDetails.requestedAmount)
        notExpired
    {
        __mint(permit, transferDetails, owner, signature);
    }

    function __mint(IPermit2.PermitTransferFrom calldata permit, IPermit2.SignatureTransferDetails calldata transferDetails, address owner, bytes calldata signature)
        private
        nonReentrant
        validAmount(transferDetails.requestedAmount)
    {
        PERMIT2.permitTransferFrom(permit, transferDetails, owner, signature);
        _mint(owner, transferDetails.requestedAmount);
    }

    function _redeem(address to, uint256 amount)
        private
        nonReentrant
        sufficientBalance(to, amount)
        validAmount(amount)
    {
        uint256 collateralBalance = collateral.balanceOf(address(this));
        uint256 considerationBalance = consideration.balanceOf(address(this));

        // First try to fulfill with collateral
        uint256 collateralToSend = amount <= collateralBalance ? amount : collateralBalance;

        // Burn the redeemed tokens
        _burn(to, amount);
        // If we couldn't fully fulfill with collateral, try to fulfill remainder with consideration
        if (collateralToSend < amount) {
            uint256 remainingAmount = amount - collateralToSend;
            uint256 considerationNeeded = toConsideration(remainingAmount);

            // Verify we have enough consideration tokens; this should never happen
            if (considerationBalance < considerationNeeded) {
                revert InsufficientBalance();
            }

            // Transfer consideration tokens for the remaining amount
            consideration.safeTransfer(to, considerationNeeded);
        }

        // Transfer whatever collateral we can
        if (collateralToSend > 0) {
            collateral.safeTransfer(to, collateralToSend);
        }
        emit Redemption(address(longOption), to, amount);
    }

    function _redeemConsideration(address to, uint256 amount)
        private
        nonReentrant
        sufficientBalance(to, amount)
        validAmount(amount)
    {
        // Verify we have enough consideration tokens
        uint256 considerationAmount = toConsideration(amount);
        if (consideration.balanceOf(address(this)) < considerationAmount) revert InsufficientBalance();
        _burn(to, amount);
        consideration.safeTransfer(to, considerationAmount);
        emit Redemption(address(longOption), to, amount);
    }

    function redeem(uint256 amount) public expired sufficientBalance(msg.sender, amount) {
        _redeem(msg.sender, amount);
    }

    function _redeemPair(address to, uint256 amount) public notExpired onlyOwner sufficientBalance(to, amount) {
        _redeem(to, amount);
    }

    function redeemConsideration(uint256 amount) public sufficientBalance(msg.sender, amount) {
        _redeemConsideration(msg.sender, amount);
    }

    function _exercise(
        IPermit2.PermitTransferFrom calldata permit, 
        IPermit2.SignatureTransferDetails calldata transferDetails, 
        address owner, 
        bytes calldata signature
        ) public notExpired onlyOwner nonReentrant {
        if (consideration.balanceOf(owner) < transferDetails.requestedAmount) revert InsufficientBalance();
        
        PERMIT2.permitTransferFrom(permit, transferDetails, owner, signature);
    }

    function exercise(
        IPermit2.PermitTransferFrom calldata permit, 
        IPermit2.SignatureTransferDetails calldata transferDetails, 
        address owner, 
        bytes calldata signature
        ) public notExpired onlyOwner {
        _exercise(permit, transferDetails, owner, signature);
    }

    function sweep(address holder) public expired sufficientBalance(holder, balanceOf(holder)) {
        _redeem(holder, balanceOf(holder));
    }
}
