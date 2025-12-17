// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { Initializable } from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import { ReentrancyGuardTransient } from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";
import { IERC20, ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

using SafeERC20 for IERC20;
// import { OptionBase } from "./OptionBase.sol";
// import { AddressSet } from "./AddressSet.sol";

using SafeERC20 for IERC20;
// using AddressSet for AddressSet.Set;
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
*/

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
    uint40 expiration;
    uint96 strike;
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

contract Redemption is ERC20, Ownable, ReentrancyGuardTransient, Initializable {
    // ============ STORAGE LAYOUT (OPTIMIZED FOR PACKING) ============

    // Account tracking removed for gas optimization
    // Users can sweep individual addresses or use off-chain indexing for batch sweep
    // address[] private _accounts;  // REMOVED: costs ~47k gas per new minter
    // mapping(address => bool) private accountsSet;  // REMOVED

    // Slot N: uint256 values (32 bytes each, separate slots)
    uint256 fees;
    uint256 public strike;

    // Slot N+2: Packed slot (20 + 8 + 5 + 1 + 1 + 1 = 36 bytes - EXCEEDS 32, split needed)
    // Better: Pack addresses together, then small types together

    // Slot N+2: collateral (20 bytes) + consideration (20 bytes) - WAIT, 40 bytes total, needs 2 slots
    IERC20 public collateral; // 20 bytes - Slot N+2

    // Slot N+3: consideration (20 bytes) + _factory (20 bytes) - 40 bytes, needs 2 slots
    IERC20 public consideration; // 20 bytes - Slot N+3

    // Slot N+4: _factory (20 bytes) + fee (8 bytes) + expirationDate (5 bytes) = 33 bytes - SPLIT
    IFactory public _factory; // 20 bytes - Slot N+4
    uint64 public fee; // 8 bytes - Same slot as _factory

    // Slot N+5: expirationDate (5 bytes) + isPut (1 byte) + locked (1 byte) + consDecimals (1 byte) + collDecimals (1 byte) = 9 bytes - FITS!
    uint40 public expirationDate; // 5 bytes - New slot N+5
    bool public isPut; // 1 byte - Same slot
    bool public locked; // 1 byte - Same slot (defaults to false)
    uint8 consDecimals; // 1 byte - Same slot
    uint8 collDecimals; // 1 byte - Same slot
    // 23 bytes remaining in this slot

    uint8 public constant STRIKE_DECIMALS = 18; // Not stored (constant)

    // ============ END STORAGE LAYOUT ============

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

    event Redeemed(address option, address token, address holder, uint256 amount);

    modifier notLocked() {
        if (locked) revert LockedContract();
        _;
    }

    modifier sufficientCollateral(address account, uint256 amount) {
        if (collateral.balanceOf(account) < amount) revert InsufficientCollateral();
        _;
    }

    modifier sufficientConsideration(address account, uint256 amount) {
        uint256 consAmount = toConsideration(amount);
        if (consideration.balanceOf(account) < consAmount) revert InsufficientConsideration();
        _;
    }

    // saveAccount modifier removed - _update already handles adding to _accounts

    // _update override removed - no longer tracking accounts for gas optimization

    constructor(
        string memory name_,
        string memory symbol_,
        address collateral_,
        address consideration_,
        uint256 expirationDate_,
        uint256 strike_,
        bool isPut_
    ) ERC20(name_, symbol_) Ownable(msg.sender) Initializable() { }

    function init(
        address collateral_,
        address consideration_,
        uint40 expirationDate_,
        uint256 strike_,
        bool isPut_,
        address option_,
        address factory_,
        uint64 fee_
    ) public initializer {
        if (collateral_ == address(0)) revert InvalidAddress();
        if (consideration_ == address(0)) revert InvalidAddress();
        if (factory_ == address(0)) revert InvalidAddress();
        if (strike_ == 0) revert InvalidValue();
        if (expirationDate_ < block.timestamp) revert InvalidValue();

        // _tokenName = name_;
        // _tokenSymbol = symbol_;
        collateral = IERC20(collateral_);
        consideration = IERC20(consideration_);
        expirationDate = expirationDate_;
        strike = strike_;
        isPut = isPut_;
        _factory = IFactory(factory_);
        fee = fee_;
        consDecimals = IERC20Metadata(consideration_).decimals();
        collDecimals = IERC20Metadata(collateral_).decimals();
        _transferOwnership(option_);
    }

    function mint(address account, uint256 amount)
        public
        onlyOwner
        notExpired
        notLocked
        nonReentrant
        validAmount(amount)
        validAddress(account)
    {
        // Defense-in-depth: verify no fee-on-transfer despite factory blocklist
        uint256 balanceBefore = collateral.balanceOf(address(this));

        _factory.transferFrom(account, address(this), uint160(amount), address(collateral));

        // Verify full amount received (costs ~3.2k gas but provides important safety)
        if (collateral.balanceOf(address(this)) - balanceBefore != amount) {
            revert FeeOnTransferNotSupported();
        }

        // Calculate fee and mint (safe: max fee is 1%, can't overflow with unchecked)
        unchecked {
            uint256 fee_ = (amount * fee) / 1e18; // Inline fee calculation
            fees += fee_;
            _mint(account, amount - fee_);
        }
    }

    function redeem(address account) public notLocked {
        redeem(account, balanceOf(account));
    }

    function redeem(uint256 amount) public notLocked {
        redeem(msg.sender, amount);
    }

    function redeem(address account, uint256 amount) public expired notLocked nonReentrant {
        _redeem(account, amount);
    }

    /// only LongOption can call
    function _redeemPair(address account, uint256 amount) public notExpired notLocked onlyOwner {
        _redeem(account, amount);
    }

    function _redeem(address account, uint256 amount) internal sufficientBalance(account, amount) validAmount(amount) {
        uint256 balance = collateral.balanceOf(address(this));
        uint256 collateralToSend = amount <= balance ? amount : balance;

        _burn(account, collateralToSend);

        if (balance < amount) {
            // fulfill with consideration because not enough collateral
            _redeemConsideration(account, amount - balance);
        }

        if (collateralToSend > 0) {
            // Transfer remaining collateral afterwards
            collateral.safeTransfer(account, collateralToSend);
        }
        emit Redeemed(address(owner()), address(collateral), account, amount);
    }

    function redeemConsideration(uint256 amount) public notLocked {
        redeemConsideration(msg.sender, amount);
    }

    function redeemConsideration(address account, uint256 amount) public notLocked nonReentrant {
        _redeemConsideration(account, amount);
    }

    function _redeemConsideration(address account, uint256 amount)
        internal
        sufficientBalance(account, amount)
        sufficientConsideration(address(this), amount)
        validAmount(amount)
    {
        _burn(account, amount);
        uint256 consAmount = toConsideration(amount);
        consideration.safeTransfer(account, consAmount);
        emit Redeemed(address(owner()), address(consideration), account, consAmount);
    }

    function exercise(address account, uint256 amount, address caller)
        public
        notExpired
        notLocked
        onlyOwner
        nonReentrant
        sufficientConsideration(caller, amount)
        sufficientCollateral(address(this), amount)
        validAmount(amount)
    {
        _factory.transferFrom(caller, address(this), uint160(toConsideration(amount)), address(consideration));
        collateral.safeTransfer(account, amount);
    }

    function sweep(address holder) public expired notLocked nonReentrant {
        _redeem(holder, balanceOf(holder));
    }

    /// @notice Batch sweep for multiple holders (requires off-chain account indexing)
    /// @dev Pass array of holder addresses obtained from Transfer events or indexer
    function sweep(address[] calldata holders) public expired notLocked nonReentrant {
        for (uint256 i = 0; i < holders.length; i++) {
            address holder = holders[i];
            uint256 balance = balanceOf(holder);
            if (balance > 0) {
                _redeem(holder, balance);
            }
        }
    }

    function claimFees() public onlyOwner nonReentrant {
        if (msg.sender != address(_factory)) {
            revert InvalidAddress();
        }
        collateral.safeTransfer(msg.sender, fees);
        fees = 0;
    }

    function lock() public onlyOwner {
        locked = true;
    }

    function unlock() public onlyOwner {
        locked = false;
    }

    // Account tracking functions removed for gas optimization
    // Use off-chain indexing (graph protocol, event logs) to track holders

    function toConsideration(uint256 amount) public view returns (uint256) {
        uint256 consMultiple = Math.mulDiv((10 ** consDecimals), strike, (10 ** STRIKE_DECIMALS) * (10 ** collDecimals));

        (uint256 high, uint256 low) = Math.mul512(amount, consMultiple);
        if (high != 0) {
            revert ArithmeticOverflow();
        }
        return low;
    }

    function toCollateral(uint256 consAmount) public view returns (uint256) {
        uint256 collMultiple =
            Math.mulDiv((10 ** collDecimals) * (10 ** STRIKE_DECIMALS), 1, strike * (10 ** consDecimals));

        (uint256 high, uint256 low) = Math.mul512(consAmount, collMultiple);
        if (high != 0) {
            revert ArithmeticOverflow();
        }
        return low;
    }

    function toFee(uint256 amount) public view returns (uint256) {
        return Math.mulDiv(fee, amount, 1e18);
    }

    function name() public view override returns (string memory) {
        return
            string(abi.encodePacked(IERC20Metadata(address(collateral)).symbol(), "-REDEM-", uint2str(expirationDate)));
    }

    function symbol() public view override returns (string memory) {
        return name();
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

    function option() public view returns (address) {
        return owner();
    }

    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    function max(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? a : b;
    }

    /// @dev Convert uint to string for name generation
    function uint2str(uint256 _i) internal pure returns (string memory str) {
        if (_i == 0) {
            return "0";
        }
        uint256 j = _i;
        uint256 length;
        while (j != 0) {
            length++;
            j /= 10;
        }
        bytes memory bstr = new bytes(length);
        uint256 k = length;
        j = _i;
        while (j != 0) {
            bstr[--k] = bytes1(uint8(48 + j % 10));
            j /= 10;
        }
        str = string(bstr);
    }
}
