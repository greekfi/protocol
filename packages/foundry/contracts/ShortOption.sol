// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

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

    event Redemption(address longOption, address token, address holder, uint256 amount);

    modifier sufficientCollateral(address account, uint256 amount) {
        require(collateral.balanceOf(account) >= amount, "Insufficient Collateral");
        _;
    }

    modifier sufficientConsideration(address account, uint256 amount) {
        uint256 consAmount = toConsideration(amount);
        require(consideration.balanceOf(account) >= consAmount, "Insufficient Consideration");
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

    function mint(address to, uint256 amount)
        public
        onlyOwner
        validAmount(amount)
        notExpired
    {
        __mint(to, amount);
    }

    function __mint(address to, uint256 amount)
        private   
        nonReentrant
        validAmount(amount)
        validAddress(to)
    {
        if (collateral.allowance(to, address(this)) >= amount) {
            collateral.safeTransferFrom(to, address(this), amount);
        } else {
            PERMIT2.transferFrom(to, address(this), uint160(amount), address(collateral));
        }
        _mint(to, amount);
    }

    function redeem(uint256 amount) public expired sufficientBalance(msg.sender, amount) {
        _redeem(msg.sender, amount);
    }

    function redeem(address to, uint256 amount) public expired sufficientBalance(to, amount) {
        _redeem(to, amount);
    }

    function _redeemPair(address to, uint256 amount) public notExpired onlyOwner sufficientBalance(to, amount) {
        // only LongOption can call
        _redeem(to, amount);
    }

    function _redeem(address to, uint256 amount)
        private
        nonReentrant
        sufficientBalance(to, amount)
        validAmount(amount)
    {
        uint256 balance = collateral.balanceOf(address(this));
        uint256 collateralToSend = amount <= balance ? amount : balance;

        _burn(to, collateralToSend);
        // fulfill with consideration first
        if (balance < amount) {
            _redeemConsideration(to, amount - balance);
        }

        // Transfer whatever collateral afterwards
        if (collateralToSend > 0) {
            collateral.safeTransfer(to, collateralToSend);
        }
        emit Redemption(address(longOption), address(collateral), to, amount);
    }

    function redeemConsideration(uint256 amount)
        public
        sufficientBalance(msg.sender, amount)
        validAmount(amount)
        nonReentrant
    {
        _redeemConsideration(msg.sender, amount);
    }
    function _redeemConsideration(address to, uint256 amount)
        private
        
        sufficientBalance(to, amount)
        sufficientConsideration(address(this), amount)
        validAmount(amount)
    {
        _burn(to, amount);
        uint256 consAmount = toConsideration(amount);
        consideration.safeTransfer(to, consAmount);
        emit Redemption(address(longOption), address(consideration), to, consAmount);
    }

    function transferFrom_(
        address caller,
        address from,
        address to,
        address token, 
        uint256 amount
        ) private {
        if (IERC20(token).allowance(from, caller) >= amount) {
                IERC20(token).safeTransferFrom(from, to, amount);
            } else {
                PERMIT2.transferFrom(from, to, uint160(amount), token);
            }
    }

    function exercise(
        uint256 amount, address to
        ) public notExpired onlyOwner {
        _exercise(amount, to);
    }

    function _exercise(
        uint256 amount,
        address to
        ) public 
        notExpired 
        onlyOwner nonReentrant 
        sufficientConsideration(to, amount) 
        sufficientCollateral(address(this), amount)
        validAmount(amount) {

        transferFrom_(
            address(this), 
            to, 
            address(this), 
            address(consideration), 
            toConsideration(amount));

        collateral.safeTransfer(to, amount);
    }


    function sweep(address holder) public expired sufficientBalance(holder, balanceOf(holder)) {
        _redeem(holder, balanceOf(holder));
    }
}
