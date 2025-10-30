// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import { OptionBase } from "./OptionBase.sol";

using SafeERC20 for IERC20;
using EnumerableSet for EnumerableSet.AddressSet;
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
    EnumerableSet.AddressSet private accountsWithBalance;

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

    function _update(address from, address to, uint256 value) internal override {
         super._update(from, to, value);
         
         // Add recipient to set if they have a balance (checked after super._update)
         if (to != address(0) && balanceOf(to) > 0) {
             accountsWithBalance.add(to);
         }
         
         // Remove sender from set if they have zero balance (checked after super._update)
         if (from != address(0) && balanceOf(from) == 0) {
             accountsWithBalance.remove(from);
         }
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

    function transferFrom_( address from, address to, IERC20 token, uint256 amount )internal {
        if (token.allowance(from, address(this)) >= amount) {
            token.safeTransferFrom(from, to, amount);
        } else {
            PERMIT2.transferFrom(from, to, uint160(amount), address(token));
        }
    }


    function mint(address account, uint256 amount)
        public onlyOwner notExpired nonReentrant validAmount(amount) sufficientCollateral(account, amount) validAddress(account) {

        transferFrom_(account, address(this), collateral, amount );
        _mint(account, amount);
    }

    function redeem(address account) public { redeem(account, balanceOf(account)); }
    function redeem(uint256 amount) public { redeem(msg.sender, amount); }
    function redeem(address account, uint256 amount) public expired nonReentrant{
        _redeem(account, amount);
    }
    function _redeemPair(address account, uint256 amount) public notExpired onlyOwner {
        // only LongOption can call
        _redeem(account, amount);
    }
    function _redeem(address account, uint256 amount)
        internal sufficientBalance(account, amount) validAmount(amount) {
        uint256 balance = collateral.balanceOf(address(this));
        uint256 collateralToSend = amount <= balance ? amount : balance;

        _burn(account, collateralToSend);

        if (balance < amount) { // fulfill with consideration because not enough collateral
            _redeemConsideration(account, amount - balance);
        }

        if (collateralToSend > 0) { // Transfer remaining collateral afterwards
            collateral.safeTransfer(account, collateralToSend);
        }
        emit Redemption(address(longOption), address(collateral), account, amount);
    }

    function redeemConsideration(uint256 amount) public {
        redeemConsideration(msg.sender, amount);
    }
    function redeemConsideration(address account, uint256 amount) public nonReentrant {
        _redeemConsideration(account, amount);
    }
    function _redeemConsideration(address account, uint256 amount)
        internal sufficientBalance(account, amount) sufficientConsideration(address(this), amount) validAmount(amount) {
        _burn(account, amount);
        uint256 consAmount = toConsideration(amount);
        consideration.safeTransfer(account, consAmount);
        emit Redemption(address(longOption), address(consideration), account, consAmount);
    }

    function exercise(address account, uint256 amount,  address caller
        ) public notExpired onlyOwner nonReentrant sufficientConsideration(caller, amount) sufficientCollateral(address(this), amount)
        validAmount(amount) {

        transferFrom_(caller, address(this), consideration, toConsideration(amount));
        collateral.safeTransfer(account, amount);
    }

    function sweep(address holder) public expired nonReentrant {
        _redeem(holder, balanceOf(holder));
    }

    function sweep() public expired nonReentrant {
        uint256 length = accountsWithBalance.length();
        for (uint256 i = 0; i < length; i++){
            // Always get index 0 since we remove elements as we process them
            address holder = accountsWithBalance.at(0);
            if (balanceOf(holder) > 0){
                _redeem(holder, balanceOf(holder));
            }
        }
    }
}
