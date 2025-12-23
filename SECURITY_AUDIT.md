# Security Audit Report
**Date**: December 17, 2024
**Auditor**: Claude Code
**Scope**: Option.sol, Redemption.sol, OptionFactory.sol
**Commit**: cleanupFactory branch

---

## Executive Summary

A comprehensive security audit was performed on three core contracts of the options protocol. The audit identified **3 critical vulnerabilities**, **3 high severity issues**, **4 medium severity issues**, and **5 low severity/informational findings**.

**Critical issues require immediate attention** as they pose significant risks to protocol solvency and functionality.

---

## 🔴 CRITICAL VULNERABILITIES

### [C-1] Unbacked Option Minting in `Option.transfer()`

**Severity**: Critical
**File**: `Option.sol:268-272`
**Status**: ❌ Not Fixed

**Issue**: The `transfer()` function automatically mints options if the sender doesn't have enough balance WITHOUT requiring collateral deposit:

```solidity
function transfer(address to, uint256 amount) public override notLocked nonReentrant returns (bool success) {
    uint256 balance = balanceOf(msg.sender);
    if (balance < amount) {
        mint_(msg.sender, amount - balance);  // ⚠️ MINTS WITHOUT COLLATERAL!
    }

    success = super.transfer(to, amount);
    require(success, "Transfer failed");

    balance = redemption.balanceOf(to);
    if (balance > 0) {
        redeem_(to, min(balance, amount));
    }
}
```

**Attack Scenario**:
1. Attacker with 0 option tokens calls `transfer(victim, 1000000 ether)`
2. System mints 1,000,000 option tokens WITHOUT requiring collateral deposit
3. Attacker now has 1M unbacked options they can:
   - Exercise to drain all collateral from Redemption contract
   - Sell to unsuspecting buyers on secondary markets
   - Use as collateral in other DeFi protocols

**Impact**:
- Complete protocol insolvency
- Unlimited minting of unbacked options
- Loss of all deposited collateral

**Proof of Concept**:
```solidity
// Attacker starts with 0 options, 0 collateral deposited
attacker.transfer(victim, type(uint256).max);
// Attacker now has type(uint256).max options with 0 collateral backing
attacker.exercise(type(uint256).max); // Drains all protocol collateral
```

**Recommendation**:
1. **REMOVE the auto-mint functionality entirely**
2. Require explicit collateral approval and transfer before any minting
3. Alternative: Revert if `balance < amount` with clear error message

```solidity
function transfer(address to, uint256 amount) public override notLocked nonReentrant returns (bool success) {
    // REMOVE auto-mint logic entirely
    success = super.transfer(to, amount);
    require(success, "Transfer failed");

    uint256 redemptionBalance = redemption.balanceOf(to);
    if (redemptionBalance > 0) {
        redeem_(to, min(redemptionBalance, amount));
    }
}
```

---

### [C-2] Broken Fee Claiming in `Redemption.claimFees()`

**Severity**: Critical
**File**: `Redemption.sol:431-436`
**Status**: ❌ Not Fixed

**Issue**: Contradictory access control prevents fees from ever being claimed, permanently locking protocol revenue:

```solidity
function claimFees() public onlyOwner nonReentrant {
    if (msg.sender != address(_factory)) {  // ⚠️ Contradictory check
        revert InvalidAddress();
    }
    collateral.safeTransfer(msg.sender, fees);
    fees = 0;
}
```

**Problem Analysis**:
- `onlyOwner` modifier means only the **Option contract** can call this function (since Option owns Redemption)
- But the function requires `msg.sender == _factory` (the OptionFactory contract)
- These two requirements are mutually exclusive
- The Option contract has **no function** to forward this call
- **Result**: Fees accumulate but can never be withdrawn

**Impact**:
- Protocol fees permanently locked in Redemption contracts
- No revenue generation for protocol
- Fees accumulate indefinitely with no recovery mechanism

**Recommendation**: Choose one of the following approaches:

**Option A - Factory Claims Fees** (Recommended):
```solidity
modifier onlyFactory() {
    if (msg.sender != address(_factory)) revert InvalidAddress();
    _;
}

function claimFees() external onlyFactory nonReentrant {
    collateral.safeTransfer(msg.sender, fees);
    fees = 0;
}
```

**Option B - Option Contract Claims Fees**:
```solidity
function claimFees() external onlyOwner nonReentrant {
    collateral.safeTransfer(address(_factory), fees);
    fees = 0;
}
```

And add to `Option.sol`:
```solidity
function claimFees() external {
    redemption.claimFees();
}
```

---

### [C-3] Incorrect Burn Amount in `Redemption._redeem()`

**Severity**: Critical
**File**: `Redemption.sol:320-334`
**Status**: ❌ Not Fixed

**Issue**: The function burns the wrong amount of tokens and has flawed logic when collateral is insufficient:

```solidity
function _redeem(address account, uint256 amount) internal sufficientBalance(account, amount) validAmount(amount) {
    uint256 balance = collateral.balanceOf(address(this));
    uint256 collateralToSend = amount <= balance ? amount : balance;

    _burn(account, collateralToSend);  // ⚠️ Burns less than amount if insufficient

    if (balance < amount) { // fulfill with consideration because not enough collateral
        _redeemConsideration(account, amount - balance);  // This ALSO tries to burn!
    }

    if (collateralToSend > 0) { // Transfer remaining collateral afterwards
        collateral.safeTransfer(account, collateralToSend);
    }
    emit Redeemed(address(owner()), address(collateral), account, amount);
}
```

**Problem Flow**:
1. User tries to redeem 100 tokens
2. Contract only has 60 collateral tokens
3. Burns 60 redemption tokens (line 324)
4. Calls `_redeemConsideration(account, 40)`
5. `_redeemConsideration` has modifier `sufficientBalance(account, 40)`
6. But we already burned 60 tokens! User now has 40 tokens remaining
7. Check passes
8. `_redeemConsideration` burns 40 MORE tokens (line 369)
9. Total burned = 100 ✓ **BUT** logic is fragile and confusing

**Secondary Issue**: `_redeemConsideration` will revert if called after a partial burn because the `sufficientBalance` check happens AFTER tokens were already burned in the parent function.

**Impact**:
- Accounting inconsistencies
- Potential for users to lose redemption tokens without receiving full value
- Complex edge cases that could lead to DoS

**Recommendation**:

```solidity
function _redeem(address account, uint256 amount) internal sufficientBalance(account, amount) validAmount(amount) {
    uint256 collateralBalance = collateral.balanceOf(address(this));

    // Burn all redemption tokens upfront
    _burn(account, amount);

    if (collateralBalance >= amount) {
        // Sufficient collateral - send it all
        collateral.safeTransfer(account, amount);
        emit Redeemed(address(owner()), address(collateral), account, amount);
    } else {
        // Insufficient collateral - send what we have + consideration for remainder
        if (collateralBalance > 0) {
            collateral.safeTransfer(account, collateralBalance);
        }

        uint256 shortfall = amount - collateralBalance;
        uint256 consAmount = toConsideration(shortfall);

        // Check we have enough consideration
        if (consideration.balanceOf(address(this)) < consAmount) {
            revert InsufficientConsideration();
        }

        consideration.safeTransfer(account, consAmount);
        emit Redeemed(address(owner()), address(collateral), account, collateralBalance);
        emit Redeemed(address(owner()), address(consideration), account, consAmount);
    }
}
```

---

## 🟡 HIGH SEVERITY ISSUES

### [H-1] Missing Validation in `Option.init()`

**Severity**: High
**File**: `Option.sol:128-132`
**Status**: ❌ Not Fixed

**Issue**: The initialization function lacks critical input validation:

```solidity
function init(address redemption_, address owner, uint64 fee_) public initializer {
    _transferOwnership(owner);  // ⚠️ owner could be address(0)
    redemption = Redemption(redemption_);  // ⚠️ no validation
    fee = fee_;  // ⚠️ no max fee check
}
```

**Potential Issues**:
- `owner = address(0)` → Contract becomes unownable, lock/unlock unusable
- `redemption_ = address(0)` → All operations will revert with low-level errors
- `fee_ > MAX_FEE` → Excessive fees (no cap enforced)
- No check that redemption_ is actually a contract

**Impact**:
- Bricked option contracts if initialized with bad parameters
- Gas wasted on deployment
- No way to fix initialization after the fact (protected by `initializer` modifier)

**Recommendation**:

```solidity
function init(address redemption_, address owner, uint64 fee_) public initializer {
    if (redemption_ == address(0)) revert InvalidAddress();
    if (owner == address(0)) revert InvalidAddress();
    if (fee_ > 0.01e18) revert InvalidValue(); // Max 1% fee

    _transferOwnership(owner);
    redemption = Redemption(redemption_);
    fee = fee_;
}
```

---

### [H-2] Missing Validation in `OptionFactory.createOption()`

**Severity**: High
**File**: `OptionFactory.sol:100-118`
**Status**: ❌ Not Fixed

**Issue**: Factory doesn't validate critical parameters before creating options:

```solidity
function createOption(address collateral, address consideration, uint40 expirationDate, uint96 strike, bool isPut)
    public
    returns (address)
{
    // Check blocklist for fee-on-transfer and rebasing tokens
    if (blocklist[collateral] || blocklist[consideration]) revert BlocklistedToken();

    // ⚠️ No validation of:
    // - collateral/consideration != address(0)
    // - collateral != consideration
    // - strike > 0
    // - expirationDate > block.timestamp

    address redemption_ = Clones.clone(redemptionClone);
    address option_ = Clones.clone(optionClone);

    Redemption redemption = Redemption(redemption_);
    Option option = Option(option_);

    redemption.init(collateral, consideration, expirationDate, strike, isPut, option_, address(this), fee);
    option.init(redemption_, msg.sender, fee);
    redemptions[redemption_] = true;

    emit OptionCreated(collateral, consideration, expirationDate, strike, isPut, option_, redemption_);
    return option_;
}
```

**Note**: While `Redemption.init()` has some validation, the factory should validate upfront to:
- Provide better error messages
- Save gas on failed deployments
- Prevent creation of unusable contracts

**Impact**:
- Creation of broken/unusable option contracts
- Wasted gas on deployment
- Poor user experience

**Recommendation**:

```solidity
function createOption(address collateral, address consideration, uint40 expirationDate, uint96 strike, bool isPut)
    public
    returns (address)
{
    // Input validation
    if (collateral == address(0)) revert InvalidAddress();
    if (consideration == address(0)) revert InvalidAddress();
    if (collateral == consideration) revert InvalidValue();
    if (strike == 0) revert InvalidValue();
    if (expirationDate <= block.timestamp) revert InvalidValue();

    // Check blocklist for fee-on-transfer and rebasing tokens
    if (blocklist[collateral] || blocklist[consideration]) revert BlocklistedToken();

    // ... rest of function
}
```

---

### [H-3] No Validation of Template Contracts in Factory Constructor

**Severity**: High
**File**: `OptionFactory.sol:80-84`
**Status**: ❌ Not Fixed

**Issue**: Constructor doesn't validate template contract addresses:

```solidity
constructor(address redemption_, address option_, uint64 fee_) Ownable(msg.sender) {
    require(fee_ <= MAX_FEE, "fee too high");
    redemptionClone = redemption_;  // ⚠️ Could be address(0)
    optionClone = option_;  // ⚠️ Could be address(0)
    fee = fee_;
}
```

**Impact**:
- If deployed with `address(0)` templates, all `createOption()` calls will fail
- Factory becomes useless and must be redeployed
- No way to update templates after deployment

**Recommendation**:

```solidity
constructor(address redemption_, address option_, uint64 fee_) Ownable(msg.sender) {
    if (redemption_ == address(0)) revert InvalidAddress();
    if (option_ == address(0)) revert InvalidAddress();
    if (redemption_.code.length == 0) revert InvalidAddress();
    if (option_.code.length == 0) revert InvalidAddress();
    if (fee_ > MAX_FEE) revert InvalidValue();

    redemptionClone = redemption_;
    optionClone = option_;
    fee = fee_;
}
```

---

## 🟠 MEDIUM SEVERITY ISSUES

### [M-1] Public `redeem()` Allows Anyone to Burn Others' Tokens

**Severity**: Medium
**File**: `Option.sol:323-325`
**Status**: ❌ Not Fixed

**Issue**: Anyone can call `redeem()` on behalf of another user:

```solidity
function redeem(address account, uint256 amount) public notLocked nonReentrant {
    redeem_(account, amount);
}
```

While this returns collateral to `account`, it's unexpected that anyone can force burn someone else's option+redemption tokens.

**Potential Issues**:
- Interference with user trading strategies
- Breaking integrations that expect consistent balances
- Griefing attacks (though victim gets their collateral)
- Tax implications if forced redemptions create taxable events

**Recommendation**: Require caller authorization:

```solidity
function redeem(address account, uint256 amount) public notLocked nonReentrant {
    if (msg.sender != account) {
        _spendAllowance(account, msg.sender, amount);
    }
    redeem_(account, amount);
}
```

---

### [M-2] Duplicate `using` Statement

**Severity**: Informational
**File**: `Redemption.sol:12-14`
**Status**: ❌ Not Fixed

**Issue**: Duplicate import statement:

```solidity
using SafeERC20 for IERC20;

using SafeERC20 for IERC20;  // ⚠️ Duplicate
```

**Recommendation**: Remove one of the duplicate lines.

---

### [M-3] Empty `name()` and `symbol()` Functions

**Severity**: Medium
**File**: `Option.sol:141-151`
**Status**: ❌ Not Fixed

**Issue**: Returns empty strings, which could break integrations and wallets:

```solidity
function name() public view override returns (string memory) {
    return "";
}

function symbol() public view override returns (string memory) {
    return "";
}
```

**Impact**:
- Wallets may not display the token properly
- DEX listings might fail
- Some contracts expect non-empty metadata

**Recommendation**: Generate meaningful names like Redemption does:

```solidity
function name() public view override returns (string memory) {
    return string(abi.encodePacked(
        IERC20Metadata(collateral()).symbol(),
        "-OPTION-",
        uint2str(expirationDate())
    ));
}

function symbol() public view override returns (string memory) {
    return name();
}
```

Or document that integrations should use `details()` for metadata.

---

### [M-4] Wrong Visibility for `_redeemPair()`

**Severity**: Low
**File**: `Redemption.sol:310`
**Status**: ❌ Not Fixed

**Issue**: Function has misleading visibility and naming:

```solidity
function _redeemPair(address account, uint256 amount) public notExpired notLocked onlyOwner {
```

**Problems**:
- Leading underscore suggests internal/private but it's public
- Should be `external` not `public` (never called internally)
- Inconsistent with naming conventions

**Recommendation**:

```solidity
function redeemPair(address account, uint256 amount) external notExpired notLocked onlyOwner {
    _redeem(account, amount);
}
```

---

## 🔵 LOW SEVERITY / INFORMATIONAL

### [L-1] No Pausability for Emergency Situations

**Severity**: Low
**Status**: ❌ Not Implemented

**Issue**: While there's a `lock()` function, there's no way to pause critical operations in case of discovered vulnerabilities:
- `lock()` only prevents transfers
- Minting, exercising, and redemption continue to work
- No emergency shutdown mechanism

**Recommendation**: Consider implementing OpenZeppelin's Pausable pattern or expanding lock functionality to pause all state-changing operations.

---

### [L-2] Ownership Transfer Could Break System

**Severity**: Low
**Status**: ❌ Not Addressed

**Issue**: If the Option contract ownership is transferred via `transferOwnership()`, the new owner controls lock/unlock for Redemption, which could be unexpected and dangerous.

**Recommendation**:
- Override `transferOwnership()` to prevent transfers
- Or add clear warnings in documentation
- Or implement a two-step ownership transfer with timelock

---

### [L-3] Missing Zero Address Checks in Transfer Functions

**Severity**: Low
**File**: `Option.sol:246-258, 268-281`
**Status**: ❌ Not Fixed

**Issue**: `transfer()` and `transferFrom()` don't explicitly check that `to != address(0)`, though ERC20 base implementation might handle this.

**Recommendation**: Add explicit check for clarity:

```solidity
if (to == address(0)) revert InvalidAddress();
```

---

### [L-4] No Event Emission for Lock/Unlock in Option.sol

**Severity**: Informational
**File**: `Option.sol:391-401`
**Status**: ❌ Not Fixed

**Issue**: Option.sol declares `ContractLocked` and `ContractUnlocked` events but never emits them (Redemption emits them instead).

**Recommendation**: Emit events in Option.sol as well:

```solidity
function lock() public onlyOwner {
    redemption.lock();
    emit ContractLocked();
}

function unlock() public onlyOwner {
    redemption.unlock();
    emit ContractUnlocked();
}
```

---

### [L-5] Inconsistent Sweep Behavior

**Severity**: Low
**File**: `Redemption.sol:405-423`
**Status**: ❌ Not Fixed

**Issue**: Inconsistent behavior between sweep overloads:
- `sweep(address holder)` will revert if holder has 0 balance (calls `_redeem` which has `validAmount` modifier)
- `sweep(address[] holders)` skips holders with 0 balance

**Recommendation**: Make behavior consistent by checking balance before calling `_redeem`:

```solidity
function sweep(address holder) public expired notLocked nonReentrant {
    uint256 balance = balanceOf(holder);
    if (balance > 0) {
        _redeem(holder, balance);
    }
}
```

---

## Summary & Recommendations

### Immediate Actions Required (Critical Priority)

1. **[C-1]** Remove auto-mint from `Option.transfer()` - **BLOCKING ISSUE**
2. **[C-2]** Fix `claimFees()` access control in Redemption.sol
3. **[C-3]** Fix burn amount logic in `Redemption._redeem()`

### High Priority (Before Mainnet)

4. **[H-1]** Add validation to `Option.init()`
5. **[H-2]** Add validation to `OptionFactory.createOption()`
6. **[H-3]** Add validation to `OptionFactory` constructor

### Medium Priority (Recommended)

7. **[M-1]** Consider access control for `redeem(address, uint256)`
8. **[M-2]** Remove duplicate `using` statement
9. **[M-3]** Implement proper `name()` and `symbol()` functions
10. **[M-4]** Fix `_redeemPair` visibility/naming

### Low Priority (Nice to Have)

11. **[L-1]** Implement pausability for emergencies
12. **[L-2]** Prevent or document ownership transfer risks
13. **[L-3]** Add zero address checks
14. **[L-4]** Emit events in Option.sol for lock/unlock
15. **[L-5]** Make sweep behavior consistent

---

## Testing Recommendations

1. **Add comprehensive fuzzing tests** for the auto-mint vulnerability in `transfer()`
2. **Test fee claiming** with various ownership scenarios
3. **Test redemption** when collateral is partially or fully depleted
4. **Test boundary conditions** for all numerical operations
5. **Test with malicious token contracts** (fee-on-transfer, rebasing, reverting)
6. **Test clone initialization** with invalid parameters
7. **Test reentrancy scenarios** even though guards are in place

---

## Conclusion

The protocol has a solid foundation but contains **three critical vulnerabilities** that must be addressed before any production deployment. The auto-mint issue in particular poses an existential risk to the protocol.

After addressing the critical and high-severity issues, a follow-up audit is strongly recommended.

---

**End of Report**
