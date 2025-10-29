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

    function mint(IPermit2.PermitTransferFrom calldata permit, IPermit2.SignatureTransferDetails calldata transferDetails, bytes calldata signature)
        public
        nonReentrant
        validAmount(transferDetails.requestedAmount)
        notExpired
    {
        shortOption_.mint(permit, transferDetails, msg.sender, signature);
        _mint(msg.sender, transferDetails.requestedAmount);
        emit Mint(address(this), msg.sender, transferDetails.requestedAmount);
    }
    function mint(uint256 amount) public {mint(amount, msg.sender); }
    function mint(uint256 amount, address to)
        public
        nonReentrant
        validAmount(amount)
        notExpired 
    {
        shortOption_.mint(to, amount);
        _mint(to, amount);
        emit Mint(address(this), to, amount);
    }


    function transferFrom(address from, address to, uint256 amount) 
    public override returns (bool success) {
        success = super.transferFrom(from, to, amount);
        uint256 shortBalance = shortOption_.balanceOf(to);
        if (shortBalance > 0){
            redeem(min(shortBalance, amount), to);
        }
        
    }

    function transfer(address to, uint256 amount) public override notLocked returns (bool success) {
        uint256 balance = this.balanceOf(msg.sender);
        // allows JIT minting
        if (balance < amount){
            mint(amount - balance);
        }

        success = super.transfer(to, amount);
        if (!success){
            revert("Transfer failed");
        }
        uint256 shortBalance = shortOption_.balanceOf(to);
        if (shortBalance > 0){
            redeem(min(shortBalance, amount), to);
        }
    }

    function exercise(IPermit2.PermitTransferFrom calldata permit, IPermit2.SignatureTransferDetails calldata transferDetails, bytes calldata signature)
        public
        notExpired
        nonReentrant
        validAmount(transferDetails.requestedAmount)
    {
        _burn(msg.sender, transferDetails.requestedAmount);
        shortOption_.exercise(permit, transferDetails, msg.sender, signature);
        emit Exercise(address(this), msg.sender, transferDetails.requestedAmount);
    }

    function exercise(uint256 amount) public { exercise(amount, msg.sender); }
    function exercise(uint256 amount, address to)
        public
        notExpired
        nonReentrant
        validAmount(amount)
    {
        _burn(to, amount);
        shortOption_.exercise(amount, to);
        emit Exercise(address(this), to, amount);
    }

    function redeem(uint256 amount) public { redeem(amount, msg.sender); }
    function redeem(uint256 amount, address to)
        public
        notExpired
        nonReentrant
        sufficientBalance(to, amount)
        validAmount(amount)
    {
        _burn(to, amount);
        shortOption_._redeemPair(to, amount);
    }

    function setShortOption(address shortOptionAddress) public onlyOwner {
        shortOption = shortOptionAddress;
        shortOption_ = ShortOption(shortOptionAddress);
    }

    function balancesOf(address account) public view returns (uint256 collBalance, uint256 consBalance, uint256 longBalance, uint256 shortBalance) {
        collBalance = collateral.balanceOf(account);
        consBalance = consideration.balanceOf(account);
        longBalance = balanceOf(account);
        shortBalance = balanceOf(account);
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
