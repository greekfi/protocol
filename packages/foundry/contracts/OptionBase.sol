// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { IPermit2 } from "./interfaces/IPermit2.sol";

import "@openzeppelin/contracts/proxy/Clones.sol";

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

contract OptionBase is ERC20, Ownable, ReentrancyGuard {
    IPermit2 public constant PERMIT2 = IPermit2(0x000000000022D473030F116dDEE9F6B43aC78BA3);
    uint256 public expirationDate;
    uint256 public strike;
    uint256 public constant STRIKE_DECIMALS = 10 ** 18;
    // The strike price includes the ratio of the consideration to the collateral
    // and the decimal difference between the consideration and collateral along
    // with the strike decimals of 18.
    bool public isPut;
    IERC20 public collateral;
    IERC20 public consideration;
    bool public initialized = false;
    string private _tokenName;
    string private _tokenSymbol;

    error ContractNotExpired();
    error ContractExpired();
    error InsufficientBalance();
    error InvalidValue();

    modifier expired() {
        if (block.timestamp < expirationDate) revert ContractNotExpired();
        _;
    }

    modifier notExpired() {
        if (block.timestamp >= expirationDate) revert ContractExpired();

        _;
    }

    modifier validAmount(uint256 amount) {
        if (amount == 0) revert InvalidValue();
        _;
    }

    modifier sufficientBalance(address contractHolder, uint256 amount) {
        if (balanceOf(contractHolder) < amount) revert InsufficientBalance();
        _;
    }

    constructor(
        string memory name_,
        string memory symbol_,
        address collateral_,
        address consideration_,
        uint256 expirationDate_,
        uint256 strike_,
        bool isPut_
    ) ERC20(name_, symbol_) Ownable(msg.sender) ReentrancyGuard() {
        if (collateral_ == address(0)) revert InvalidValue();
        if (consideration_ == address(0)) revert InvalidValue();
        if (strike_ == 0) revert InvalidValue();
        if (expirationDate_ < block.timestamp) revert InvalidValue();

        expirationDate = expirationDate_;
        strike = strike_;
        isPut = isPut_;
        collateral = IERC20(collateral_);
        consideration = IERC20(consideration_);
    }

    function toConsideration(uint256 amount) public view returns (uint256) {
        // The strike price actually contains the ratio of Consideration
        // over Collateral including the decimals associated. The ratio is
        // multiplied by 10**18 as is the standard convention. That's why
        // we eventually divide by the STRIKE_DECIMALS. MulDiv?
        return (amount * strike) / STRIKE_DECIMALS;
    }

    function init(
        string memory name_,
        string memory symbol_,
        address collateral_,
        address consideration_,
        uint256 expirationDate_,
        uint256 strike_,
        bool isPut_
    ) public {
        require(!initialized, "already init");
        initialized = true;
        if (collateral_ == address(0)) revert InvalidValue();
        if (consideration_ == address(0)) revert InvalidValue();
        if (strike_ == 0) revert InvalidValue();
        if (expirationDate_ < block.timestamp) revert InvalidValue();
        
        _tokenName = name_;
        _tokenSymbol = symbol_;
        collateral = IERC20(collateral_);
        consideration = IERC20(consideration_);
        expirationDate = expirationDate_;
        strike = strike_;
        isPut = isPut_;

        // set owner so factory can call restricted functions
        _transferOwnership(msg.sender);
    }

    function name() public view override returns (string memory) {
        return _tokenName;
    }

    function symbol() public view override returns (string memory) {
        return _tokenSymbol;
    }
}
