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

import { TokenData } from "./interfaces/IOption.sol";
import { OptionUtils } from "./OptionUtils.sol";
import { IPriceOracle } from "./oracles/IPriceOracle.sol";

interface IFactoryTransfer {
    function transferFrom(address from, address to, uint160 amount, address token) external;
}

/**
 * @title Collateral
 * @notice Short-side ERC20. Holds all collateral; receives consideration on exercise (American only).
 * @dev Supports three modes:
 *        - American non-settled (oracle = 0, !isEuro): exercise + pro-rata redeem + redeemConsideration
 *        - American settled    (oracle != 0, !isEuro): exercise + oracle-settled redeem + redeemConsideration
 *        - European            (oracle != 0, isEuro):  no exercise; oracle-settled redeem + claim
 *      (oracle=0 && isEuro is rejected at the factory.)
 *
 *      Post-expiry in settled modes: redeem pays pro-rata of `(collateralBalance - optionReserve, considerationBalance)`
 *      where `optionReserve` is the un-exercised collateral claimable by option holders (ITM share).
 *      Option holders call Option.claim → Collateral._claimForOption to collect their (S-K)/S payout.
 *      Reserve is initialized once on first settle() call post-expiry.
 *
 *      Rounding: floor on all payouts. Dust stays in contract.
 */
contract Collateral is ERC20, Ownable, ReentrancyGuardTransient, Initializable {
    // slot 0
    uint256 public strike;
    // slot 1: latched on first settle; 0 if never settled or non-settled mode
    uint256 public settlementPrice;
    // slot 2: un-exercised collateral reserved for option-holder ITM claims, decremented on each claim
    uint256 public optionReserveRemaining;
    // slot 3
    IERC20 public collateral;
    // slot 4
    IERC20 public consideration;
    // slot 5
    IFactoryTransfer public _factory;
    // slot 6
    IPriceOracle public oracle; // zero address in American non-settled
    // slot 7: packed — 5 + 1 + 1 + 1 + 1 + 1 + 1 = 11 bytes
    uint40 public expirationDate;
    bool public isPut;
    bool public isEuro;
    bool public locked;
    uint8 public consDecimals;
    uint8 public collDecimals;
    bool public reserveInitialized;

    uint8 public constant STRIKE_DECIMALS = 18;

    error ContractNotExpired();
    error ContractExpired();
    error InsufficientBalance();
    error InvalidValue();
    error InvalidAddress();
    error LockedContract();
    error FeeOnTransferNotSupported();
    error InsufficientCollateral();
    error InsufficientConsideration();
    error ArithmeticOverflow();
    error NoOracle();
    error NotSettled();
    error SettledOnly();
    error NonSettledOnly();
    error EuropeanExerciseDisabled();

    event Redeemed(address option, address token, address holder, uint256 amount);
    event Settled(uint256 price);

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

    modifier sufficientBalance(address account, uint256 amount) {
        if (balanceOf(account) < amount) revert InsufficientBalance();
        _;
    }

    modifier notLocked() {
        if (locked) revert LockedContract();
        _;
    }

    modifier sufficientCollateral(uint256 amount) {
        if (collateral.balanceOf(address(this)) < amount) revert InsufficientCollateral();
        _;
    }

    modifier sufficientConsideration(address account, uint256 amount) {
        uint256 consAmount = toConsideration(amount);
        if (consideration.balanceOf(account) < consAmount) revert InsufficientConsideration();
        _;
    }

    constructor(string memory name_, string memory symbol_) ERC20(name_, symbol_) Ownable(msg.sender) {
        _disableInitializers();
    }

    function init(
        address collateral_,
        address consideration_,
        uint40 expirationDate_,
        uint256 strike_,
        bool isPut_,
        bool isEuro_,
        address oracle_,
        address option_,
        address factory_
    ) public initializer {
        if (collateral_ == address(0)) revert InvalidAddress();
        if (consideration_ == address(0)) revert InvalidAddress();
        if (factory_ == address(0)) revert InvalidAddress();
        if (option_ == address(0)) revert InvalidAddress();
        if (strike_ == 0) revert InvalidValue();
        if (expirationDate_ < block.timestamp) revert InvalidValue();

        collateral = IERC20(collateral_);
        consideration = IERC20(consideration_);
        expirationDate = expirationDate_;
        strike = strike_;
        isPut = isPut_;
        isEuro = isEuro_;
        _factory = IFactoryTransfer(factory_);
        oracle = IPriceOracle(oracle_); // may be zero
        consDecimals = IERC20Metadata(consideration_).decimals();
        collDecimals = IERC20Metadata(collateral_).decimals();
        _transferOwnership(option_);
    }

    // ============ MINT ============

    function mint(address account, uint256 amount)
        public
        onlyOwner
        notExpired
        notLocked
        nonReentrant
        validAmount(amount)
        validAddress(account)
    {
        if (amount > type(uint160).max) revert ArithmeticOverflow();

        uint256 balanceBefore = collateral.balanceOf(address(this));
        // forge-lint: disable-next-line(unsafe-typecast)
        _factory.transferFrom(account, address(this), uint160(amount), address(collateral));
        if (collateral.balanceOf(address(this)) - balanceBefore != amount) {
            revert FeeOnTransferNotSupported();
        }

        _mint(account, amount);
    }

    // ============ PRE-EXPIRY PAIR REDEEM (called by Option) ============

    function _redeemPair(address account, uint256 amount) public notExpired notLocked onlyOwner nonReentrant {
        _redeemPairInternal(account, amount);
    }

    function _redeemPairInternal(address account, uint256 amount)
        internal
        sufficientBalance(account, amount)
        validAmount(amount)
    {
        // Waterfall: collateral first, consideration fallback (defense-in-depth).
        uint256 balance = collateral.balanceOf(address(this));
        uint256 collateralToSend = amount <= balance ? amount : balance;

        _burn(account, collateralToSend);

        if (balance < amount) {
            _redeemConsideration(account, amount - balance);
        }

        if (collateralToSend > 0) {
            collateral.safeTransfer(account, collateralToSend);
        }
        emit Redeemed(address(owner()), address(collateral), account, collateralToSend);
    }

    // ============ EXERCISE (American only) ============

    function exercise(address account, uint256 amount, address caller)
        public
        notExpired
        notLocked
        onlyOwner
        nonReentrant
        sufficientCollateral(amount)
        validAmount(amount)
    {
        if (isEuro) revert EuropeanExerciseDisabled();

        uint256 consAmount = toNeededConsideration(amount);
        if (consideration.balanceOf(caller) < consAmount) revert InsufficientConsideration();
        if (consAmount == 0) revert InvalidValue();
        if (consAmount > type(uint160).max) revert ArithmeticOverflow();

        uint256 consBefore = consideration.balanceOf(address(this));
        // forge-lint: disable-next-line(unsafe-typecast)
        _factory.transferFrom(caller, address(this), uint160(consAmount), address(consideration));
        if (consideration.balanceOf(address(this)) - consBefore < consAmount) revert FeeOnTransferNotSupported();
        collateral.safeTransfer(account, amount);
    }

    // ============ POST-EXPIRY REDEEM ============

    /// @notice Redeem all caller's coll tokens post-expiry
    function redeem() public notLocked {
        redeem(msg.sender, balanceOf(msg.sender));
    }

    /// @notice Redeem `amount` coll tokens for msg.sender post-expiry
    function redeem(uint256 amount) public notLocked {
        redeem(msg.sender, amount);
    }

    /// @notice Redeem `amount` coll tokens for `account` post-expiry. Routes to settled or pro-rata path.
    function redeem(address account, uint256 amount) public expired notLocked nonReentrant {
        if (address(oracle) != address(0)) {
            _settle("");
            _redeemSettled(account, amount);
        } else {
            _redeemProRata(account, amount);
        }
    }

    function _redeemProRata(address account, uint256 amount)
        internal
        sufficientBalance(account, amount)
        validAmount(amount)
    {
        uint256 ts = totalSupply();
        uint256 collateralBalance = collateral.balanceOf(address(this));
        uint256 collateralToSend = Math.mulDiv(amount, collateralBalance, ts);
        uint256 remainder = amount - collateralToSend;

        _burn(account, amount);

        if (collateralToSend > 0) {
            collateral.safeTransfer(account, collateralToSend);
        }
        if (remainder > 0) {
            uint256 consToSend = toConsideration(remainder);
            if (consToSend > 0) consideration.safeTransfer(account, consToSend);
        }
        emit Redeemed(address(owner()), address(collateral), account, collateralToSend);
    }

    function _redeemSettled(address account, uint256 amount)
        internal
        sufficientBalance(account, amount)
        validAmount(amount)
    {
        uint256 ts = totalSupply();
        uint256 collBalance = collateral.balanceOf(address(this));
        uint256 reserve = optionReserveRemaining;
        uint256 availableColl = collBalance > reserve ? collBalance - reserve : 0;
        uint256 collToSend = Math.mulDiv(amount, availableColl, ts);
        uint256 consBalance = consideration.balanceOf(address(this));
        uint256 consToSend = consBalance > 0 ? Math.mulDiv(amount, consBalance, ts) : 0;

        _burn(account, amount);
        if (collToSend > 0) collateral.safeTransfer(account, collToSend);
        if (consToSend > 0) consideration.safeTransfer(account, consToSend);
        emit Redeemed(address(owner()), address(collateral), account, collToSend);
    }

    // ============ REDEEM CONSIDERATION (American only) ============

    function redeemConsideration(uint256 amount) public notLocked nonReentrant {
        if (isEuro) revert EuropeanExerciseDisabled();
        _redeemConsideration(msg.sender, amount);
    }

    function _redeemConsideration(address account, uint256 collAmount)
        internal
        sufficientBalance(account, collAmount)
        sufficientConsideration(address(this), collAmount)
        validAmount(collAmount)
    {
        _burn(account, collAmount);
        uint256 consAmount = toConsideration(collAmount);
        if (consAmount == 0) revert InvalidValue();
        consideration.safeTransfer(account, consAmount);
        emit Redeemed(address(owner()), address(consideration), account, consAmount);
    }

    // ============ SETTLE + CLAIM (settled modes only) ============

    /// @notice Latches the oracle settlement price and initializes the option-holder reserve.
    ///         Callable by anyone post-expiry. Idempotent.
    function settle(bytes calldata hint) public notLocked {
        _settle(hint);
    }

    function _settle(bytes memory hint) internal {
        if (address(oracle) == address(0)) revert NoOracle();
        if (reserveInitialized) return;
        if (block.timestamp < expirationDate) revert ContractNotExpired();

        uint256 S = oracle.settle(hint);
        settlementPrice = S;
        uint256 K = strike;
        if (S > K) {
            uint256 O = IERC20(owner()).totalSupply();
            optionReserveRemaining = Math.mulDiv(O, S - K, S);
        }
        reserveInitialized = true;
        emit Settled(S);
    }

    /// @notice Option-holder ITM payout. Only callable by paired Option contract.
    /// @return payout Collateral units sent to holder (floor-rounded).
    function _claimForOption(address holder, uint256 amount) external onlyOwner returns (uint256 payout) {
        _settle("");
        uint256 S = settlementPrice;
        uint256 K = strike;
        if (S > K) {
            payout = Math.mulDiv(amount, S - K, S);
            uint256 reserve = optionReserveRemaining;
            if (payout > reserve) payout = reserve;
            if (payout > 0) {
                optionReserveRemaining = reserve - payout;
                collateral.safeTransfer(holder, payout);
            }
        }
        return payout;
    }

    // ============ SWEEPS ============

    function sweep(address holder) public expired notLocked nonReentrant {
        uint256 amount = balanceOf(holder);
        if (amount == 0) return;
        if (address(oracle) != address(0)) {
            _settle("");
            _redeemSettled(holder, amount);
        } else {
            _redeemProRata(holder, amount);
        }
    }

    function sweep(address[] calldata holders) public expired notLocked nonReentrant {
        bool settled_ = address(oracle) != address(0);
        if (settled_) _settle("");
        for (uint256 i = 0; i < holders.length; i++) {
            address holder = holders[i];
            uint256 bal = balanceOf(holder);
            if (bal == 0) continue;
            if (settled_) {
                _redeemSettled(holder, bal);
            } else {
                _redeemProRata(holder, bal);
            }
        }
    }

    // ============ ADMIN ============

    function lock() public onlyOwner {
        locked = true;
    }

    function unlock() public onlyOwner {
        locked = false;
    }

    // ============ CONVERSIONS ============

    function toConsideration(uint256 amount) public view returns (uint256) {
        return Math.mulDiv(amount, strike * (10 ** consDecimals), (10 ** STRIKE_DECIMALS) * (10 ** collDecimals));
    }

    function toNeededConsideration(uint256 amount) public view returns (uint256) {
        return Math.mulDiv(
            amount, strike * (10 ** consDecimals), (10 ** STRIKE_DECIMALS) * (10 ** collDecimals), Math.Rounding.Ceil
        );
    }

    function toCollateral(uint256 consAmount) public view returns (uint256) {
        return Math.mulDiv(consAmount, (10 ** collDecimals) * (10 ** STRIKE_DECIMALS), strike * (10 ** consDecimals));
    }

    // ============ METADATA ============

    function name() public view override returns (string memory) {
        uint256 displayStrike = isPut ? (1e36 / strike) : strike;
        return string(
            abi.encodePacked(
                isEuro ? "CLLE-" : "CLL-",
                IERC20Metadata(address(collateral)).symbol(),
                "-",
                IERC20Metadata(address(consideration)).symbol(),
                "-",
                OptionUtils.strike2str(displayStrike),
                "-",
                OptionUtils.epoch2str(expirationDate)
            )
        );
    }

    function symbol() public view override returns (string memory) {
        return name();
    }

    function decimals() public view override returns (uint8) {
        return collDecimals;
    }

    function collateralData() public view returns (TokenData memory) {
        IERC20Metadata m = IERC20Metadata(address(collateral));
        return TokenData({ address_: address(collateral), name: m.name(), symbol: m.symbol(), decimals: m.decimals() });
    }

    function considerationData() public view returns (TokenData memory) {
        IERC20Metadata m = IERC20Metadata(address(consideration));
        return
            TokenData({ address_: address(consideration), name: m.name(), symbol: m.symbol(), decimals: m.decimals() });
    }

    function option() public view returns (address) {
        return owner();
    }

    function factory() public view returns (address) {
        return address(_factory);
    }
}
