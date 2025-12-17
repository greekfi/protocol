// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

// import { OptionBase, OptionInfo, TokenData } from "./OptionBase.sol";
import { Redemption } from "./Redemption.sol";

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { Initializable } from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import { ReentrancyGuardTransient } from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";
import { IERC20, ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

using SafeERC20 for IERC20;
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

struct TokenData {
    address address_;
    string name;
    string symbol;
    uint8 decimals;
}

struct Balances {
    uint256 collateral;
    uint256 consideration;
    uint256 option;
    uint256 redemption;
}

struct OptionInfo {
    address option;
    address redemption;
    TokenData collateral;
    TokenData consideration;
    uint256 expiration;
    uint256 strike;
    bool isPut;
}

contract Option is ERC20, Ownable, ReentrancyGuardTransient, Initializable {
    Redemption public redemption;
    uint64 public fee;
    string private _tokenName;
    string private _tokenSymbol;

    event Mint(address longOption, address holder, uint256 amount);
    event Exercise(address longOption, address holder, uint256 amount);

    error ContractNotExpired();
    error ContractExpired();
    error InsufficientBalance();
    error InvalidValue();
    error InvalidAddress();
    error LockedContract();
    error FeeOnTransferNotSupported();
    error InsufficientCollateral();
    error InsufficientConsideration();
    error TokenBlocklisted();
    error ArithmeticOverflow();

    event ContractLocked();
    event ContractUnlocked();

    modifier notLocked() {
        if (redemption.locked()) revert LockedContract();
        _;
    }

    modifier notExpired() {
        if (block.timestamp >= expirationDate()) revert ContractExpired();

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

    constructor(string memory name_, string memory symbol_, address redemption__)
        ERC20(name_, symbol_)
        Ownable(msg.sender)
    {
        redemption = Redemption(redemption__);
    }

    function init(address redemption_, address owner, uint64 fee_) public initializer {
        _transferOwnership(owner);
        redemption = Redemption(redemption_);
        fee = fee_;
    }

    function name() public view override returns (string memory) {
        return "";
    }

    function symbol() public view override returns (string memory) {
        return "";
    }

    function collateral() public view returns (address) {
        return address(redemption.collateral());
    }

    function consideration() public view returns (address) {
        return address(redemption.consideration());
    }

    function expirationDate() public view returns (uint256) {
        return redemption.expirationDate();
    }

    function strike() public view returns (uint256) {
        return redemption.strike();
    }

    function isPut() public view returns (bool) {
        return redemption.isPut();
    }

    function mint(uint256 amount) public notLocked {
        mint(msg.sender, amount);
    }

    function mint(address account, uint256 amount) public notLocked nonReentrant {
        mint_(account, amount);
    }

    function mint_(address account, uint256 amount) internal notExpired validAmount(amount) {
        redemption.mint(account, amount);
        // Inline fee calculation (safe: max fee is 1%, can't overflow)
        unchecked {
            uint256 amountMinusFees = amount - ((amount * fee) / 1e18);
            _mint(account, amountMinusFees);
            emit Mint(address(this), account, amountMinusFees);
        }
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
        uint256 balance = balanceOf(msg.sender);
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

    function exercise(uint256 amount) public notLocked {
        exercise(msg.sender, amount);
    }

    function exercise(address account, uint256 amount) public notExpired notLocked nonReentrant validAmount(amount) {
        _burn(msg.sender, amount);
        redemption.exercise(account, amount, msg.sender);
        emit Exercise(address(this), msg.sender, amount);
    }

    function redeem(uint256 amount) public notLocked {
        redeem(msg.sender, amount);
    }

    function redeem(address account, uint256 amount) public notLocked nonReentrant {
        redeem_(account, amount);
    }

    function redeem_(address account, uint256 amount) internal notExpired sufficientBalance(account, amount) {
        _burn(account, amount);
        redemption._redeemPair(account, amount);
    }

    function balancesOf(address account) public view returns (Balances memory) {
        return Balances({
            collateral: IERC20(collateral()).balanceOf(account),
            consideration: IERC20(consideration()).balanceOf(account),
            option: balanceOf(account),
            redemption: redemption.balanceOf(account)
        });
    }

    function lock() public onlyOwner {
        redemption.lock();
    }

    function unlock() public onlyOwner {
        redemption.unlock();
    }

    function details() public view returns (OptionInfo memory) {
        // Cache addresses to avoid multiple delegatecalls
        address coll = collateral();
        address cons = consideration();

        // Cache metadata objects
        IERC20Metadata consMeta = IERC20Metadata(cons);
        IERC20Metadata collMeta = IERC20Metadata(coll);

        // Cache frequently accessed values
        string memory optName = name();
        string memory optSymbol = symbol();
        string memory redName = redemption.name();
        string memory redSymbol = redemption.symbol();
        uint8 optDecimals = decimals();
        uint256 exp = expirationDate();
        uint256 stk = strike();
        bool put = isPut();

        return OptionInfo({
            option: address(this),
            redemption: address(redemption),
            collateral: TokenData(coll, collMeta.name(), collMeta.symbol(), collMeta.decimals()),
            consideration: TokenData(cons, consMeta.name(), consMeta.symbol(), consMeta.decimals()),
            expiration: exp,
            strike: stk,
            isPut: put
        });
    }

    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    function max(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? a : b;
    }
}
