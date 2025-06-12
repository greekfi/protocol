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
// The Long Option contract is the only one that can mint new mint
// The Long Option contract is the only one that can exercise mint
// The redemption is only possible if you own both the Long and Short Option contracts but
// performed by the Long Option contract

// In mint traditionally a Consideration is cash and a Collateral is an asset
// Here, we do not distinguish between the Cash and Asset concept and allow consideration
// to be any asset and collateral to be any asset as well. This can allow wETH to be used
// as collateral and wBTC to be used as consideration. Similarly, staked ETH can be used
// or even staked stable coins can be used as well for either consideration or collateral.

contract LongOption is OptionBase {
    ShortOption public shortOption;

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

    function mint(uint256 amount) public nonReentrant validAmount(amount) notExpired {
        _mint(msg.sender, amount);
        shortOption.mint(msg.sender, amount);
    }

    function mint2(uint256 amount, IPermit2.PermitSingle calldata permitDetails, bytes calldata signature)
        public
        nonReentrant
        validAmount(amount)
        notExpired
    {
        _mint(msg.sender, amount);
        shortOption.mint2(msg.sender, amount, permitDetails, signature);
    }

    function exercise(uint256 amount) public notExpired nonReentrant validAmount(amount) {
        _burn(msg.sender, amount);
        shortOption.exercise(msg.sender, amount);
        emit Exercise(address(this), msg.sender, amount);
    }

    function exercise2(uint256 amount, IPermit2.PermitSingle calldata permitDetails, bytes calldata signature)
        public
        notExpired
        nonReentrant
        validAmount(amount)
    {
        _burn(msg.sender, amount);
        shortOption.exercise2(msg.sender, amount, permitDetails, signature);
        emit Exercise(address(this), msg.sender, amount);
    }

    function redeem(uint256 amount)
        public
        notExpired
        nonReentrant
        sufficientBalance(msg.sender, amount)
        validAmount(amount)
    {
        if (shortOption.balanceOf(msg.sender) < amount) revert InsufficientBalance();

        address contractHolder = msg.sender;
        _burn(contractHolder, amount);
        shortOption._redeemPair(contractHolder, amount);
    }
}
