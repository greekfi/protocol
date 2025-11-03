// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { OptionBase } from "./OptionBase.sol";
import {Redemption} from "./Redemption.sol";
/*
The Option contract is the owner of the Redemption contract
The Option contract is the only one that can mint new mint
The Option contract is the only one that can exercise mint
The redemption is only possible if you own both the Option and
Redemption contracts but performed by the Option contract

In mint traditionally a Consideration is cash and a Collateral is an asset
Here, we do not distinguish between the Cash and Asset concept and allow consideration
to be any asset and collateral to be any asset as well. This can allow wETH to be used
as collateral and wBTC to be used as consideration. Similarly, staked ETH can be used
or even staked stable coins can be used as well for either consideration or collateral.

In minting, traditionally a Consideration is cash and a Collateral is an asset
Here, we do not distinguish between the Cash and Asset concept and allow consideration
to be any asset and collateral to be any asset as well. This can allow wETH to be used
as collateral and wBTC to be used as consideration. Similarly, staked ETH can be used
or even staked stable coins can be used as well for either consideration or collateral.

*/


struct OptionDetails {
    string optionName;
    string optionSymbol;
    string redName;
    string redSymbol;
    address collateral;
    address consideration;
    string collName;
    string consName;
    string collSymbol;
    string consSymbol;
    uint8 collDecimals;
    uint8 consDecimals;
    uint256 expirationDate;
    uint256 strike;
    bool isPut;
    uint256 totalSupply;
    bool locked;
    address redemption;
    address option;
}

contract Option is OptionBase {
    address public redemption_;
    Redemption public redemption;

    event Mint(address longOption, address holder, uint256 amount);
    event Exercise(address longOption, address holder, uint256 amount);

    constructor(
        string memory name,
        string memory symbol,
        address collateral,
        address consideration,
        uint256 expirationDate,
        uint256 strike,
        bool isPut,
        address redemption__
    ) OptionBase(name, symbol, collateral, consideration, expirationDate, strike, isPut) {
        redemption_ = redemption__;
        redemption = Redemption(redemption__);
    }

    function mint(uint256 amount) public { mint(msg.sender, amount); }
    function mint(address account, uint256 amount)
        public nonReentrant {
        mint_(account, amount);
    }
    function mint_(address account, uint256 amount)
        internal notExpired notLocked validAmount(amount) {
        redemption.mint(account, amount);
        _mint(account, amount);
        emit Mint(address(this), account, amount);
    }

    function transferFrom(address from, address to, uint256 amount) 
        public override notLocked nonReentrant returns (bool success) {
        success = super.transferFrom(from, to, amount);
        uint256 balance = redemption.balanceOf(to);
        if (balance > 0){
            redeem_(to, min(balance, amount));
        }
    }

    function transfer(address to, uint256 amount) 
        public override notLocked nonReentrant returns (bool success) {
        uint256 balance = this.balanceOf(msg.sender);
        if (balance < amount){
            mint_(msg.sender, amount - balance);
        }

        success = super.transfer(to, amount);
        require(success, "Transfer failed");

        balance = redemption.balanceOf(to);
        if (balance > 0){
            redeem_(to, min(balance, amount));
        }
    }
    function exercise(uint256 amount) public { exercise(msg.sender, amount); }
    function exercise(address account, uint256 amount) public notExpired nonReentrant validAmount(amount) {
        _burn(msg.sender, amount);
        redemption.exercise(account, amount, msg.sender);
        emit Exercise(address(this), msg.sender, amount);
    }

    function redeem(uint256 amount) public { redeem(msg.sender, amount); }
    function redeem(address account, uint256 amount)
        public nonReentrant {
        redeem_(account, amount);
    }
    function redeem_(address account, uint256 amount) internal notExpired sufficientBalance(account, amount) {
        _burn(account, amount);
        redemption._redeemPair(account, amount);
    }

    function setRedemption(address shortOptionAddress) public onlyOwner {
        redemption_ = shortOptionAddress;
        redemption = Redemption(redemption_);
    }

    function balancesOf(address account) 
    public view returns (uint256 collBalance, uint256 consBalance, uint256 optionBalance, uint256 redemptionBalance) {
        collBalance = collateral.balanceOf(account);
        consBalance = consideration.balanceOf(account);
        optionBalance = balanceOf(account);
        redemptionBalance = redemption.balanceOf(account);
    }

    function details() public view returns (OptionDetails memory) {
        return OptionDetails({
            optionName: name(),
            optionSymbol: symbol(),
            redName: redemption.name(),
            redSymbol: redemption.symbol(),
            collateral: address(collateral),
            consideration: address(consideration),
            collDecimals: collDecimals,
            consDecimals: consDecimals,
            collName: coll.name(),
            consName: cons.name(),
            collSymbol: coll.symbol(),
            consSymbol: cons.symbol(),
            expirationDate: expirationDate,
            strike: strike,
            isPut: isPut,
            totalSupply: totalSupply(),
            locked: locked,
            redemption: address(redemption_),
            option: address(this)
        });
    }
}
