// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

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

    function mint(address sender, uint256 amount)
        public
        onlyOwner
        validAmount(amount)
        notExpired
    {
        __mint(sender, amount);
    }

    function __mint(address sender, uint256 amount)
        private   
        nonReentrant
        validAmount(amount)
        validAddress(sender)
    {
        if (collateral.allowance(sender, address(this)) >= amount) {
            collateral.safeTransferFrom(sender, address(this), amount);
        } else {
            PERMIT2.transferFrom(sender, address(this), uint160(amount), address(collateral));
        }
        _mint(sender, amount);
    }

    function _redeem(address to, uint256 amount)
        private
        nonReentrant
        sufficientBalance(to, amount)
        validAmount(amount)
    {
        uint256 balance = collateral.balanceOf(address(this));
        uint256 collateralToSend = amount <= balance ? amount : balance;

        _burn(to, amount);
        // fulfill with consideration first
        if (balance < amount) {
            _redeemConsideration(to, amount - balance);
        }

        // Transfer whatever collateral afterwards
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
        uint256 considerationAmount = toConsideration(amount);
        require(consideration.balanceOf(address(this)) >= considerationAmount, "Insufficient Consideration");
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
        uint256 amount,
        address owner
        ) public notExpired onlyOwner nonReentrant {
        require(consideration.balanceOf(owner) >= amount, "Insufficient Consideration");
        if (consideration.allowance(owner, address(this)) >= amount) {
            consideration.safeTransferFrom(owner, address(this), amount);
        } else {
            PERMIT2.transferFrom(owner, address(this), uint160(amount), address(consideration));
        }

        uint256 collateralToSend = toCollateral(amount);
        require(collateral.balanceOf(address(this)) >= collateralToSend, "Insufficient Collateral");
        collateral.safeTransfer(owner, collateralToSend);
    }

    function exercise(
        uint256 amount, address owner
        ) public notExpired onlyOwner {
        _exercise(amount, owner);
    }

    function sweep(address holder) public expired sufficientBalance(holder, balanceOf(holder)) {
        _redeem(holder, balanceOf(holder));
    }
}
