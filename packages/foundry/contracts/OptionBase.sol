// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { Initializable } from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { IERC20, ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

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

// IMPORTANT: This protocol does NOT support fee-on-transfer or rebasing tokens.
// - Fee-on-transfer tokens will fail during minting due to accounting mismatches
// - Rebasing tokens will break the collateral accounting invariants
// - Use wrapped versions for rebasing tokens (e.g., wstETH instead of stETH)
// - The factory maintains a blocklist of known problematic tokens

interface IFactory {
    function transferFrom(address from, address to, uint160 amount, address token) external;
}

struct TokenData {
    address address_;
    string name;
    string symbol;
    uint8 decimals;
}

struct OptionParameter {
    string optionSymbol;
    string redemptionSymbol;
    address collateral_;
    address consideration_;
    uint256 expiration;
    uint256 strike;
    bool isPut;
}

struct OptionInfo {
    TokenData option;
    TokenData redemption;
    TokenData collateral;
    TokenData consideration;
    OptionParameter p;
    address coll; //shortcut
    address cons; //shortcut
    uint256 expiration;
    uint256 strike;
    bool isPut;
}

contract OptionBase is ERC20, Ownable, ReentrancyGuard, Initializable {
    uint256 public expirationDate;
    uint256 public strike;
    uint256 public constant STRIKE_DECIMALS = 10 ** 18;
    // The strike price includes the ratio of the consideration to the collateral
    // and the decimal difference between the consideration and collateral along
    // with the strike decimals of 18.
    bool public isPut;
    IERC20 public collateral;
    IERC20 public consideration;
    IERC20Metadata cons;
    IERC20Metadata coll;
    uint8 consDecimals;
    uint8 collDecimals;
    bool public initialized = false;
    string private _tokenName;
    string private _tokenSymbol;
    address public factory;
    IFactory public _factory;
    uint256 public fee;
    uint256 public consMultiple; // to convert option amount to consideration amount
    uint256 public collMultiple; // to convert option amount to collateral amount

    error ContractNotExpired();
    error ContractExpired();
    error InsufficientBalance();
    error InvalidValue();
    error InvalidAddress();
    error ContractLocked();
    error FeeOnTransferNotSupported();
    error InsufficientCollateral();
    error InsufficientConsideration();
    error TokenBlocklisted();

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

    modifier validAddress(address addr) {
        if (addr == address(0)) revert InvalidAddress();
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
    ) ERC20(name_, symbol_) Ownable(msg.sender) {
        if (collateral_ == address(0)) revert InvalidValue();
        if (consideration_ == address(0)) revert InvalidValue();
        if (strike_ == 0) revert InvalidValue();
        if (expirationDate_ < block.timestamp) revert InvalidValue();

        expirationDate = expirationDate_;
        strike = strike_;
        isPut = isPut_;
        collateral = IERC20(collateral_);
        consideration = IERC20(consideration_);
        _tokenName = name_;
        _tokenSymbol = symbol_;
        consMultiple = Math.mulDiv( (10 ** consDecimals), strike, STRIKE_DECIMALS * (10 ** collDecimals));
        collMultiple = Math.mulDiv( (10 ** collDecimals) * STRIKE_DECIMALS, 1, strike * (10 ** consDecimals));

    }

    function toConsideration(uint256 amount) public view returns (uint256) {
        (uint256 high, uint256 low) = Math.mul512(amount, consMultiple);
        if (high != 0) {
            revert InvalidValue();
        }
        return low;
    }

    function toCollateral(uint256 consAmount) public view returns (uint256) {
        (uint256 high, uint256 low) = Math.mul512(consAmount, collMultiple);
        if (high != 0) {
            revert InvalidValue();
        }
        return low; 
    }

    function toFee(uint256 amount) public view returns (uint256) {
        return Math.mulDiv(fee, amount, 1e18);
    }

    function init(
        string memory name_,
        string memory symbol_,
        address collateral_,
        address consideration_,
        uint256 expirationDate_,
        uint256 strike_,
        bool isPut_,
        address owner,
        address factory_,
        uint256 fee_
    ) public virtual initializer {
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
        factory = factory_;
        _factory = IFactory(factory_);
        fee = fee_;

        cons = IERC20Metadata(consideration_);
        coll = IERC20Metadata(collateral_);
        consDecimals = cons.decimals();
        collDecimals = coll.decimals();

        // set owner so factory can call restricted functions
        _transferOwnership(owner);
    }

    function name() public view override returns (string memory) {
        return _tokenName;
    }

    function symbol() public view override returns (string memory) {
        return _tokenSymbol;
    }

    function decimals() public view override returns (uint8) {
        return collDecimals;
    }

    function collateralData() public view returns (TokenData memory) {
        IERC20Metadata collateralMetadata = IERC20Metadata(address(collateral));
        return TokenData(
            address(collateral), collateralMetadata.name(), collateralMetadata.symbol(), collateralMetadata.decimals()
        );
    }

    function considerationData() public view returns (TokenData memory) {
        IERC20Metadata considerationMetadata = IERC20Metadata(address(consideration));
        return TokenData(
            address(consideration),
            considerationMetadata.name(),
            considerationMetadata.symbol(),
            considerationMetadata.decimals()
        );
    }

    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    function max(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? a : b;
    }
}
