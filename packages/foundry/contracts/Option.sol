// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { OptionBase, OptionInfo, OptionParameter, TokenData } from "./OptionBase.sol";
import { Redemption } from "./Redemption.sol";
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

struct Balances {
    uint256 collateral;
    uint256 consideration;
    uint256 option;
    uint256 redemption;
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

    function init(
        string memory name_,
        string memory symbol_,
        address collateral_,
        address consideration_,
        uint256 expirationDate_,
        uint256 strike_,
        bool isPut_,
        address redemption__,
        address owner,
        address factory_,
        uint256 fee_
    ) public {
        super.init(name_, symbol_, collateral_, consideration_, expirationDate_, strike_, isPut_, owner, factory_, fee_);
        redemption_ = redemption__;
        redemption = Redemption(redemption_);
    }

    function mint(uint256 amount) public {
        mint(msg.sender, amount);
    }

    function mint(address account, uint256 amount) public nonReentrant {
        mint_(account, amount);
    }

    function mint_(address account, uint256 amount) internal notExpired notLocked validAmount(amount) {
        redemption.mint(account, amount);
        uint256 amountMinusFees = amount - toFee(amount);
        _mint(account, amountMinusFees);
        emit Mint(address(this), account, amountMinusFees);
    }

    function transferFrom(address from, address to, uint256 amount)
        public
        override
        notLocked
        nonReentrant
        returns (bool success)
    {
        success = super.transferFrom(from, to, amount);
        uint256 balance = redemption.balanceOf(to);
        if (balance > 0) {
            redeem_(to, min(balance, amount));
        }
    }

    function transfer(address to, uint256 amount) public override notLocked nonReentrant returns (bool success) {
        uint256 balance = this.balanceOf(msg.sender);
        if (balance < amount) {
            mint_(msg.sender, amount - balance);
        }

        success = super.transfer(to, amount);
        require(success, "Transfer failed");

        balance = redemption.balanceOf(to);
        if (balance > 0) {
            redeem_(to, min(balance, amount));
        }
    }

    function exercise(uint256 amount) public {
        exercise(msg.sender, amount);
    }

    function exercise(address account, uint256 amount) public notExpired nonReentrant validAmount(amount) {
        _burn(msg.sender, amount);
        redemption.exercise(account, amount, msg.sender);
        emit Exercise(address(this), msg.sender, amount);
    }

    function redeem(uint256 amount) public {
        redeem(msg.sender, amount);
    }

    function redeem(address account, uint256 amount) public nonReentrant {
        redeem_(account, amount);
    }

    function redeem_(address account, uint256 amount) internal notExpired sufficientBalance(account, amount) {
        _burn(account, amount);
        redemption._redeemPair(account, amount);
    }

    function balancesOf(address account) public view returns (Balances memory) {
        return Balances({
            collateral: collateral.balanceOf(account),
            consideration: consideration.balanceOf(account),
            option: balanceOf(account),
            redemption: redemption.balanceOf(account)
        });
    }

    function details() public view returns (OptionInfo memory) {
        return OptionInfo({
            option: TokenData(address(this), name(), symbol(), decimals()),
            redemption: TokenData(redemption_, redemption.name(), redemption.symbol(), decimals()),
            collateral: TokenData(address(collateral), coll.name(), coll.symbol(), coll.decimals()),
            consideration: TokenData(address(consideration), cons.name(), cons.symbol(), cons.decimals()),
            p: OptionParameter({
                optionSymbol: name(),
                redemptionSymbol: redemption.name(),
                collateral_: address(collateral),
                consideration_: address(consideration),
                expiration: expirationDate,
                strike: strike,
                isPut: isPut
            }),
            coll: address(collateral),
            cons: address(consideration),
            expiration: expirationDate,
            strike: strike,
            isPut: isPut
        });
    }
}
