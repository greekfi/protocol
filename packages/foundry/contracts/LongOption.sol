// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { IPermit2 } from "./interfaces/IPermit2.sol";
import { OptionBase } from "./OptionBase.sol";
import { ShortOption } from "./ShortOption.sol";

// The Long Option contract is the owner of the Short Option contract
// The Long Option contract is the only one that can mint new 
// The Long Option contract is the only one that can exercise 
// The redemption is only possible if you own both the Long and Short Option contracts but
// performed by the Long Option contract

// In mint traditionally a Consideration is cash and a Collateral is an asset
// Here, we do not distinguish between the Cash and Asset concept and allow consideration
// to be any asset and collateral to be any asset as well. This can allow wETH to be used
// as collateral and wBTC to be used as consideration. Similarly, staked ETH can be used
// or even staked stable coins can be used as well for either consideration or collateral.

struct OptionDetails {
    string name;
    string symbol;
    string shortName;
    string shortSymbol;
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
    address shortOption;
    address longOption;
}

contract LongOption is OptionBase {
    address public shortOption;
    ShortOption public shortOption_;

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
        address shortOptionAddress_
    ) OptionBase(name, symbol, collateral, consideration, expirationDate, strike, isPut) {
        shortOption = shortOptionAddress_;
        shortOption_ = ShortOption(shortOptionAddress_);
    }

    function mint(uint256 amount) public { mint(msg.sender, amount); }
    function mint(address to, uint256 amount)
        public
        nonReentrant
        validAmount(amount)
        notExpired 
    {
        shortOption_.mint(to, amount);
        _mint(to, amount);
        emit Mint(address(this), to, amount);
    }
    function mint_(address to, uint256 amount)
        internal
        validAmount(amount)
        notExpired 
    {
        shortOption_.mint(to, amount);
        _mint(to, amount);
        emit Mint(address(this), to, amount);
    }

    function transferFrom(address from, address to, uint256 amount) 
    public override notLocked nonReentrant returns (bool success) {
        success = super.transferFrom(from, to, amount);
        uint256 balance = shortOption_.balanceOf(to);
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

        balance = shortOption_.balanceOf(to);
        if (balance > 0){
            redeem_(to, min(balance, amount));
        }
    }

    function exercise(uint256 amount)
        public
        notExpired
        nonReentrant
        validAmount(amount)
    {
        _burn(msg.sender, amount);
        shortOption_.exercise(amount, msg.sender);
        emit Exercise(address(this), msg.sender, amount);
    }

// do we need a redeemTo ?

    function redeem_(address to, uint256 amount) internal sufficientBalance(to, amount) {
        _burn(to, amount);
        shortOption_._redeemPair(to, amount);
    }

    function redeem(uint256 amount)
        public
        notExpired
        nonReentrant
        sufficientBalance(msg.sender, amount)
        validAmount(amount)
    {
        redeem_(msg.sender, amount);
    }
    function redeem(address to, uint256 amount)
        public
        notExpired
        nonReentrant
        sufficientBalance(to, amount)
        validAmount(amount)
    {
        redeem_(to, amount);
    }

    function setShortOption(address shortOptionAddress) public onlyOwner {
        shortOption = shortOptionAddress;
        shortOption_ = ShortOption(shortOption);
    }

    function balancesOf(address account) public view returns (uint256 collBalance, uint256 consBalance, uint256 longBalance, uint256 shortBalance) {
        collBalance = collateral.balanceOf(account);
        consBalance = consideration.balanceOf(account);
        longBalance = balanceOf(account);
        shortBalance = shortOption_.balanceOf(account);
    }

    function details() public view returns (OptionDetails memory) {
        return OptionDetails({
            name: name(),
            symbol: symbol(),
            shortName: shortOption_.name(),
            shortSymbol: shortOption_.symbol(),
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
            shortOption: address(shortOption),
            longOption: address(this)
        });
    }
}
