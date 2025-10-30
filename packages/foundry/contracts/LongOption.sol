// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

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
    string longName;
    string longSymbol;
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
    ShortOption public short;

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
        require(shortOptionAddress_ != address(0), "Invalid short option address");
        shortOption = shortOptionAddress_;
        short = ShortOption(shortOptionAddress_);
    }

    function mint(uint256 amount) public { mint(msg.sender, amount); }
    function mint(address account, uint256 amount)
        public nonReentrant {
        mint_(account, amount);
    }
    function mint_(address account, uint256 amount)
        internal notExpired notLocked validAmount(amount) {
        short.mint(account, amount);
        _mint(account, amount);
        emit Mint(address(this), account, amount);
    }

    function transferFrom(address from, address to, uint256 amount) 
        public override notLocked nonReentrant returns (bool success) {
        success = super.transferFrom(from, to, amount);
        uint256 balance = short.balanceOf(to);
        if (balance > 0){
            redeem_(to, min(balance, amount));
        }
    }

    function transfer(address to, uint256 amount) 
        public override notLocked nonReentrant returns (bool success) {
        success = super.transfer(to, amount);
        require(success, "Transfer failed");

        uint256 balance = short.balanceOf(to);
        if (balance > 0){
            redeem_(to, min(balance, amount));
        }
    }
    function exercise(uint256 amount) public { exercise(msg.sender, amount); }
    function exercise(address account, uint256 amount) public notExpired nonReentrant validAmount(amount) {
        _burn(msg.sender, amount);
        short.exercise(account, amount, msg.sender);
        emit Exercise(address(this), msg.sender, amount);
    }

    function redeem(uint256 amount) public { redeem(msg.sender, amount); }
    function redeem(address account, uint256 amount)
        public nonReentrant {
        redeem_(account, amount);
    }
    function redeem_(address account, uint256 amount) internal notExpired sufficientBalance(account, amount) {
        _burn(account, amount);
        short._redeemPair(account, amount);
    }

    function setShortOption(address shortOptionAddress) public onlyOwner {
        shortOption = shortOptionAddress;
        short = ShortOption(shortOption);
    }

    function balancesOf(address account) 
    public view returns (uint256 collBalance, uint256 consBalance, uint256 longBalance, uint256 shortBalance) {
        collBalance = collateral.balanceOf(account);
        consBalance = consideration.balanceOf(account);
        longBalance = balanceOf(account);
        shortBalance = short.balanceOf(account);
    }

    function details() public view returns (OptionDetails memory) {
        return OptionDetails({
            longName: name(),
            longSymbol: symbol(),
            shortName: short.name(),
            shortSymbol: short.symbol(),
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
