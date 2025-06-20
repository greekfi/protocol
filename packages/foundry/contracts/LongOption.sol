// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { IPermit2 } from "./interfaces/IPermit2.sol";

import "@openzeppelin/contracts/proxy/Clones.sol";

import { OptionBase } from "./OptionBase.sol";
import { ShortOption } from "./ShortOption.sol";

using SafeERC20 for IERC20;
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

contract LongOption is OptionBase {
    ShortOption public shortOption;

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
        shortOption = ShortOption(shortOptionAddress_);
    }

    function mint(IPermit2.PermitTransferFrom calldata permit, IPermit2.SignatureTransferDetails calldata transferDetails, bytes calldata signature)
        public
        nonReentrant
        validAmount(transferDetails.requestedAmount)
        notExpired
    {
        shortOption.mint(permit, transferDetails, msg.sender, signature);
        _mint(msg.sender, transferDetails.requestedAmount);
        emit Mint(address(this), msg.sender, transferDetails.requestedAmount);
    }

    function exercise(IPermit2.PermitTransferFrom calldata permit, IPermit2.SignatureTransferDetails calldata transferDetails, bytes calldata signature)
        public
        notExpired
        nonReentrant
        validAmount(transferDetails.requestedAmount)
    {
        _burn(msg.sender, transferDetails.requestedAmount);
        shortOption.exercise(permit, transferDetails, msg.sender, signature);
        emit Exercise(address(this), msg.sender, transferDetails.requestedAmount);
    }

    function redeem(uint256 amount)
        public
        notExpired
        nonReentrant
        sufficientBalance(msg.sender, amount)
        validAmount(amount)
    {
        _burn(msg.sender, amount);
        shortOption._redeemPair(msg.sender, amount);
    }

    function setShortOption(address shortOptionAddress) public onlyOwner {
        shortOption = ShortOption(shortOptionAddress);
    }
}
