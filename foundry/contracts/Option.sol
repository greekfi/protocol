// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { Initializable } from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import { ReentrancyGuardTransient } from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";
import { IERC20, ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

import { Collateral } from "./Collateral.sol";
import { TokenData, Balances, OptionInfo } from "./interfaces/IOption.sol";
import { OptionUtils } from "./OptionUtils.sol";
import { IPriceOracle } from "./oracles/IPriceOracle.sol";

interface IFactoryView {
    function approvedOperator(address owner, address operator) external view returns (bool);
    function autoMintRedeem(address account) external view returns (bool);
}

/**
 * @title Option
 * @notice Long-side ERC20. Three modes (chosen at creation, see Factory):
 *        - American non-settled: exercise pre-expiry; no post-expiry claim
 *        - American settled:    exercise pre-expiry; post-expiry claim pays ITM residual
 *        - European:            no exercise; post-expiry claim pays ITM residual
 *
 *      Mode is read from paired Collateral (`isEuro`, `oracle`).
 *
 *      Opt-in auto-settling transfers via `factory.autoMintRedeem`:
 *        - Auto-mint: transfer > balance mints the deficit from collateral
 *        - Auto-redeem: receiving Options while holding Coll tokens burns matched pairs
 */
contract Option is ERC20, Ownable, ReentrancyGuardTransient, Initializable {
    Collateral public coll;

    event Mint(address longOption, address holder, uint256 amount);
    event Exercise(address longOption, address holder, uint256 amount);
    event Settled(uint256 price);
    event Claimed(address indexed holder, uint256 optionBurned, uint256 collateralOut);
    event ContractLocked();
    event ContractUnlocked();

    error ContractExpired();
    error ContractNotExpired();
    error InsufficientBalance();
    error InvalidValue();
    error InvalidAddress();
    error LockedContract();
    error EuropeanExerciseDisabled();
    error NoOracle();

    modifier notLocked() {
        if (coll.locked()) revert LockedContract();
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

    modifier sufficientBalance(address account, uint256 amount) {
        if (balanceOf(account) < amount) revert InsufficientBalance();
        _;
    }

    constructor(string memory name_, string memory symbol_) ERC20(name_, symbol_) Ownable(msg.sender) {
        _disableInitializers();
    }

    function init(address coll_, address owner_) public initializer {
        if (coll_ == address(0) || owner_ == address(0)) revert InvalidAddress();
        coll = Collateral(coll_);
        _transferOwnership(owner_);
    }

    // ============ VIEWS ============

    function factory() public view returns (address) {
        return coll.factory();
    }

    function collateral() public view returns (address) {
        return address(coll.collateral());
    }

    function consideration() public view returns (address) {
        return address(coll.consideration());
    }

    function expirationDate() public view returns (uint256) {
        return coll.expirationDate();
    }

    function strike() public view returns (uint256) {
        return coll.strike();
    }

    function isPut() public view returns (bool) {
        return coll.isPut();
    }

    function isEuro() public view returns (bool) {
        return coll.isEuro();
    }

    function oracle() public view returns (address) {
        return address(coll.oracle());
    }

    function isSettled() public view returns (bool) {
        return coll.reserveInitialized();
    }

    function settlementPrice() public view returns (uint256) {
        return coll.settlementPrice();
    }

    function decimals() public view override returns (uint8) {
        return IERC20Metadata(collateral()).decimals();
    }

    function name() public view override returns (string memory) {
        uint256 displayStrike = isPut() && strike() > 0 ? (1e36 / strike()) : strike();
        return string(
            abi.encodePacked(
                isEuro() ? "OPTE-" : "OPT-",
                IERC20Metadata(collateral()).symbol(),
                "-",
                IERC20Metadata(consideration()).symbol(),
                "-",
                OptionUtils.strike2str(displayStrike),
                "-",
                OptionUtils.epoch2str(expirationDate())
            )
        );
    }

    function symbol() public view override returns (string memory) {
        return name();
    }

    // ============ MINT ============

    function mint(uint256 amount) public notLocked {
        mint(msg.sender, amount);
    }

    function mint(address account, uint256 amount) public notLocked nonReentrant {
        mint_(account, amount);
    }

    function mint_(address account, uint256 amount) internal notExpired validAmount(amount) {
        coll.mint(account, amount);
        _mint(account, amount);
        emit Mint(address(this), account, amount);
    }

    // ============ TRANSFER (auto-mint + auto-redeem) ============

    function _settledTransfer(address from, address to, uint256 amount) internal {
        uint256 balance = balanceOf(from);
        if (balance < amount) {
            if (!IFactoryView(factory()).autoMintRedeem(from)) revert InsufficientBalance();
            uint256 deficit = amount - balance;
            mint_(from, deficit);
        }

        _transfer(from, to, amount);

        if (IFactoryView(factory()).autoMintRedeem(to)) {
            uint256 collBal = coll.balanceOf(to);
            if (collBal > 0) {
                redeem_(to, Math.min(collBal, amount));
            }
        }
    }

    function transfer(address to, uint256 amount) public override notExpired notLocked nonReentrant returns (bool) {
        _settledTransfer(msg.sender, to, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount)
        public
        override
        notExpired
        notLocked
        nonReentrant
        returns (bool)
    {
        if (msg.sender != from && !IFactoryView(factory()).approvedOperator(from, msg.sender)) {
            _spendAllowance(from, msg.sender, amount);
        }
        _settledTransfer(from, to, amount);
        return true;
    }

    // ============ EXERCISE (American only) ============

    function exercise(uint256 amount) public notLocked {
        exercise(msg.sender, amount);
    }

    function exercise(address account, uint256 amount) public notExpired notLocked nonReentrant validAmount(amount) {
        if (isEuro()) revert EuropeanExerciseDisabled();
        _burn(msg.sender, amount);
        coll.exercise(account, amount, msg.sender);
        emit Exercise(address(this), msg.sender, amount);
    }

    // ============ PRE-EXPIRY PAIR REDEEM ============

    function redeem(uint256 amount) public notLocked nonReentrant {
        redeem_(msg.sender, amount);
    }

    function redeem_(address account, uint256 amount) internal notExpired sufficientBalance(account, amount) {
        _burn(account, amount);
        coll._redeemPair(account, amount);
    }

    // ============ POST-EXPIRY SETTLE + CLAIM (settled modes only) ============

    function settle(bytes calldata hint) external notLocked {
        if (address(coll.oracle()) == address(0)) revert NoOracle();
        coll.settle(hint);
        emit Settled(coll.settlementPrice());
    }

    function claim(uint256 amount)
        external
        notLocked
        nonReentrant
        validAmount(amount)
        sufficientBalance(msg.sender, amount)
    {
        if (address(coll.oracle()) == address(0)) revert NoOracle();
        if (block.timestamp < expirationDate()) revert ContractNotExpired();
        // Latch reserve using current option supply BEFORE the burn (idempotent).
        coll.settle("");
        _burn(msg.sender, amount);
        uint256 payout = coll._claimForOption(msg.sender, amount);
        emit Claimed(msg.sender, amount, payout);
    }

    function claimFor(address holder) external notLocked nonReentrant {
        if (address(coll.oracle()) == address(0)) revert NoOracle();
        if (block.timestamp < expirationDate()) revert ContractNotExpired();
        uint256 bal = balanceOf(holder);
        if (bal == 0) return;
        coll.settle("");
        _burn(holder, bal);
        uint256 payout = coll._claimForOption(holder, bal);
        emit Claimed(holder, bal, payout);
    }

    // ============ QUERY ============

    function balancesOf(address account) public view returns (Balances memory) {
        return Balances({
            collateral: IERC20(collateral()).balanceOf(account),
            consideration: IERC20(consideration()).balanceOf(account),
            option: balanceOf(account),
            coll: coll.balanceOf(account)
        });
    }

    function details() public view returns (OptionInfo memory) {
        address colTok = collateral();
        address consTok = consideration();
        IERC20Metadata cm = IERC20Metadata(colTok);
        IERC20Metadata cnm = IERC20Metadata(consTok);
        return OptionInfo({
            option: address(this),
            coll: address(coll),
            collateral: TokenData({ address_: colTok, name: cm.name(), symbol: cm.symbol(), decimals: cm.decimals() }),
            consideration: TokenData({
                address_: consTok,
                name: cnm.name(),
                symbol: cnm.symbol(),
                decimals: cnm.decimals()
            }),
            expiration: expirationDate(),
            strike: strike(),
            isPut: isPut(),
            isEuro: isEuro(),
            oracle: oracle()
        });
    }

    // ============ ADMIN ============

    function lock() public onlyOwner {
        coll.lock();
        emit ContractLocked();
    }

    function unlock() public onlyOwner {
        coll.unlock();
        emit ContractUnlocked();
    }

    function renounceOwnership() public pure override {
        revert InvalidAddress();
    }
}
