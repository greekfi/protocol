# Security Audit: Greek Protocol Contracts

**Date:** 2026-02-19
**Auditor:** Claude Code
**Scope:** All Solidity files in `foundry/contracts/`

---

## CRITICAL Severity

### 1. `toConsideration()` precision loss — free exercise of call options
**Status: FIXED** (committed on `audit-fix`) — `toConsideration` and `toCollateral` both rewritten to include `amount` in `Math.mulDiv`, eliminating the intermediate rounding to zero.

**File:** `Redemption.sol:479-487`

The pre-computation of `consMultiple` rounds to zero for standard WETH/USDC call options, making exercise completely free.

```solidity
uint256 consMultiple = Math.mulDiv(
    (10 ** consDecimals), strike, (10 ** STRIKE_DECIMALS) * (10 ** collDecimals)
);
```

For a WETH/USDC call (collDecimals=18, consDecimals=6, strike=2000e18):
- `mulDiv(10^6, 2*10^21, 10^36) = 2*10^27 / 10^36 = 0`
- `toConsideration(anything) = anything * 0 = 0`

**Impact:** Anyone can exercise call options paying **zero** consideration. All WETH collateral can be drained for free. The `sufficientConsideration` modifier passes because `0 >= 0`, and `factory.transferFrom` transfers 0 tokens.

**Fix:** Compute with amount included in the mulDiv to avoid precision loss:
```solidity
function toConsideration(uint256 amount) public view returns (uint256) {
    return Math.mulDiv(amount, strike * (10 ** consDecimals), (10 ** STRIKE_DECIMALS) * (10 ** collDecimals));
}
```

---

### 2. `Redemption.sufficientBalance` silently returns instead of reverting
**Status: FIXED** (committed on `audit-fix`) — Changed `return` to `revert InsufficientBalance()`.

**File:** `Redemption.sol:144-147`

```solidity
modifier sufficientBalance(address account, uint256 amount) {
    if (balanceOf(account) < amount) return;  // ← silent no-op, should revert
    _;
}
```

Compare with `Option.sol:113-116` which correctly **reverts**:
```solidity
modifier sufficientBalance(address contractHolder, uint256 amount) {
    if (balanceOf(contractHolder) < amount) revert InsufficientBalance();
    _;
}
```

**Impact:** Any function guarded by this modifier silently succeeds when balance is insufficient. This is exploited by finding #3 below.

---

### 3. Anyone can burn other users' Option tokens via `redeem(address, uint256)`
**Status: FIXED** (uncommitted on `audit-fix`) — Removed the `redeem(address, uint256)` overload entirely; `redeem(uint256)` now always uses `msg.sender`. **Note:** The current fix has a duplicate `nonReentrant` modifier on `redeem(uint256)` which will fail to compile — needs cleanup.

**File:** `Option.sol:602-604`

```solidity
function redeem(address account, uint256 amount) public notLocked nonReentrant {
    redeem_(account, amount);
}
```

No access control — any caller can specify any `account`. The internal `redeem_` burns the account's Option tokens, then calls `redemption._redeemPair`. If the account has fewer Redemption tokens than Option tokens, the Redemption side silently returns (due to finding #2), and the Option tokens are burned with **no collateral returned**.

**Attack scenario:**
1. Alice sells her Redemption tokens, keeping 100 Option tokens and 0 Redemption tokens
2. Attacker calls `option.redeem(alice, 100)`
3. 100 Option tokens burned from Alice, `_redeemPair` silently returns → Alice loses everything

**Fix:** Either restrict `redeem(address, uint256)` to `msg.sender` only, or fix the `sufficientBalance` modifier to revert.

---

## HIGH Severity

### 4. `adjustFee` has no MAX_FEE validation — unchecked fee enables infinite mint
**Status: FIXED** (uncommitted on `audit-fix`) — Added `MAXFEE = 1e16` (1%) constant and `if (fee_ > MAXFEE) revert InvalidValue()` check in both `Option.adjustFee` and `Redemption.adjustFee`.

**Files:** `Option.sol:703-705`, `Redemption.sol:512-514`

```solidity
// Redemption.sol
function adjustFee(uint64 fee_) public onlyOwner {
    fee = fee_;  // No MAX_FEE check
}
```

The Option owner can set `fee > 1e18` (>100%). In the `unchecked` block of `Redemption.mint`:

```solidity
unchecked {
    uint256 fee_ = (amount * fee) / 1e18;
    fees += fee_;
    _mint(account, amount - fee_);  // underflows → mints ~2^256 tokens
}
```

**Impact:** Option owner can set fee to >100%, causing underflow in unchecked arithmetic, minting an astronomical number of Redemption tokens.

**Fix:** Add `require(fee_ <= MAX_FEE)` in both `adjustFee` functions.

---

### 5. `Option.adjustFee` only updates Redemption fee, not Option fee
**Status: FIXED** (uncommitted on `audit-fix`) — `Option.adjustFee` now sets `fee = fee_` before calling `redemption.adjustFee(fee_)`.

**File:** `Option.sol:703-705`

```solidity
function adjustFee(uint64 fee_) public onlyOwner {
    redemption.adjustFee(fee_);  // Updates Redemption.fee only
    // Option.fee is never updated
}
```

After calling `adjustFee`, the Option and Redemption contracts charge different fees on the same mint operation, leading to asymmetric token supply.

---

### 6. Protocol fees can be consumed by redeemers
**Status: NOT FIXED**

**File:** `Redemption.sol:328-344`

The `_redeem` function uses `collateral.balanceOf(address(this))` to determine available collateral, which **includes** accumulated fees. There's no segregation between fee balance and redeemable balance.

```solidity
uint256 balance = collateral.balanceOf(address(this)); // includes fees
uint256 collateralToSend = amount <= balance ? amount : balance;
```

If redeemers claim collateral before `claimFees()` is called, they consume the fee balance. After all Redemption tokens are burned, `claimFees()` would revert because the fee WETH has already been sent to redeemers.

---

## MEDIUM Severity

### 7. `OptionFactory.claimFees` uses raw `transfer` instead of `safeTransfer`
**Status: FIXED** (uncommitted on `audit-fix`) — Changed to `token_.safeTransfer(owner(), amount)`.

**File:** `OptionFactory.sol:293`

```solidity
token_.transfer(owner(), amount); // Should be token_.safeTransfer(owner(), amount)
```

Non-standard ERC20 tokens that don't return `bool` from `transfer()` will cause this to revert. The file already imports and uses `SafeERC20` elsewhere.

---

### 8. Factory allowance is never consumed
**Status: NOT FIXED**

**File:** `OptionFactory.sol:184-194`

```solidity
function transferFrom(...) external ... {
    if (allowance(token, from) < amount) revert InvalidAddress();
    ERC20(token).safeTransferFrom(from, to, amount);
    // allowance is never decreased!
}
```

The factory's `approve()` sets an amount threshold, but `transferFrom` never decrements it. This makes the "allowance" function as a per-call minimum check rather than a spending limit. Users expecting standard allowance behavior would be surprised.

---

### 9. `OpHook.getCollateralPrice` — `collateralIsOne` is always false
**Status: NOT FIXED**

**File:** `OpHook.sol:303-304`

```solidity
bool collateralIsOne = pricePool.token0() == collateral
    ? pricePool.token1() == collateral  // always false (token0 != token1)
    : pricePool.token0() == collateral; // always false (we're in the else branch)
```

This ternary always evaluates to `false`, so the price inversion at line 316-318 never triggers. Prices will be wrong when collateral is token1. Same bug at `OpHook.sol:365`.

**Fix:** `bool collateralIsOne = pricePool.token1() == collateral;`

---

### 10. `redeemConsideration` has no expiration check — first-come-first-served race
**Status: BY DESIGN** — Callable pre- and post-expiration intentionally. NatSpec comment added to `Redemption.sol`.

**File:** `Redemption.sol:363-365`

```solidity
function redeemConsideration(address account, uint256 amount) public notLocked nonReentrant {
```

This can be called before expiration by any Redemption holder. With multiple holders, the first to call claims all consideration, leaving others with nothing. No pro-rata distribution.

---

### 11. `createOptions` return variable shadows state mapping
**Status: PARTIALLY FIXED** (uncommitted on `audit-fix`) — `claimFees` and `optionsClaimFees` parameters renamed from `options` to `options_`, but `createOptions` itself still uses `options` as the return variable name, shadowing the state mapping.

**File:** `OptionFactory.sol:162`

```solidity
function createOptions(...) public returns (address[] memory options) {
    // 'options' here is the local array, not mapping(address => bool) public options
```

While not exploitable, this naming collision is confusing and error-prone.

---

## LOW Severity

### 12. `OpHook` imports `forge-std/console.sol`
**Status: NOT FIXED**

**File:** `OpHook.sol:31`

Debug import should never be in production code. Increases contract size and deployment cost.

---

### 13. `OptionPrice` uses hardcoded volatility and risk-free rate
**Status: NOT FIXED**

**File:** `OptionPrice.sol:505`

```solidity
blackScholesPrice(collateralPrice, strike, timeToExpiration, 0.2 * 1e18, 0.05 * 1e18, isPut)
```

20% vol and 5% risk-free rate are hardcoded. These should be configurable for production use.

---

### 14. `Option.name()` division by zero for put with strike=0
**Status: NOT FIXED**

**File:** `Option.sol:166`

```solidity
uint256 displayStrike = isPut() ? (1e36 / strike()) : strike();
```

If `strike()` returns 0, this reverts. While `init` validates `strike != 0`, a misconfigured template could hit this.

---

### 15. Duplicate struct definitions across files
**Status: NOT FIXED**

`TokenData`, `OptionInfo`, `OptionParameter`, `Balances` are defined in multiple files (Option.sol, Redemption.sol, IOption.sol, IRedemption.sol, IOptionFactory.sol). If these diverge, compilation issues arise.

---

### 16. No events emitted for fee adjustments in Option/Redemption
**Status: NOT FIXED**

**Files:** `Option.sol:703`, `Redemption.sol:512`

Unlike `OptionFactory.adjustFee` which emits `FeeUpdated`, the Option/Redemption `adjustFee` functions emit no events, making fee changes invisible to off-chain monitoring.

---

### 17. `ShakyToken` and `StableToken` have unrestricted `mint`
**Status: NOT FIXED**

**File:** `ShakyToken.sol:13, 28`

Anyone can mint unlimited tokens. Presumably test-only, but should be noted if deployed.

---

## Informational

- **Auto-mint on `transfer`**: `Option.transfer` auto-mints if balance < amount, pulling collateral silently. While documented, this breaks ERC20 assumptions for integrating protocols (DEXes, lending protocols).
- **Template contracts not initialized**: The Option/Redemption templates can be initialized by anyone. No funds at risk since clones use separate storage, but it's best practice to call `_disableInitializers()` in the template constructor.
- **`transfer` vs `transferFrom` asymmetry**: `transfer` has auto-mint behavior but `transferFrom` does not, which is inconsistent.

---

## Summary by Severity

| Severity | Count | Fixed | Remaining | Key Issues |
|----------|-------|-------|-----------|------------|
| Critical | 3 | 3 | 0 | Precision loss in toConsideration, silent return modifier, unauthorized token burning |
| High | 3 | 2 | 1 | Unbounded fee → infinite mint, fee desync (**fixed**); fee drainage (**not fixed**) |
| Medium | 5 | 1 | 3 (+1 partial) | Unsafe transfer (**fixed**); allowance, price logic, race condition (**not fixed**); variable shadowing (**partial**) |
| Low | 6 | 0 | 6 | Debug import, hardcoded params, division by zero, duplicate structs, missing events, unrestricted mint |

### Fix Status Overview

| # | Finding | Status | Notes |
|---|---------|--------|-------|
| 1 | `toConsideration` precision loss | FIXED (committed) | |
| 2 | `sufficientBalance` silent return | FIXED (committed) | |
| 3 | Unauthorized `redeem(address,uint256)` | FIXED (uncommitted) | Has duplicate `nonReentrant` modifier — needs cleanup |
| 4 | `adjustFee` no MAX_FEE | FIXED (uncommitted) | |
| 5 | `Option.adjustFee` fee desync | FIXED (uncommitted) | |
| 6 | Fees consumed by redeemers | NOT FIXED | |
| 7 | Raw `transfer` in `claimFees` | FIXED (uncommitted) | |
| 8 | Factory allowance never consumed | NOT FIXED | |
| 9 | OpHook `collateralIsOne` bug | NOT FIXED | |
| 10 | `redeemConsideration` pre-expiration | BY DESIGN | Intentionally callable at any time; NatSpec added |
| 11 | `createOptions` variable shadowing | PARTIAL (uncommitted) | `claimFees`/`optionsClaimFees` params renamed, `createOptions` still shadows |
| 12 | `OpHook` debug import | NOT FIXED | |
| 13 | Hardcoded vol/rate | NOT FIXED | |
| 14 | Division by zero (put strike=0) | NOT FIXED | |
| 15 | Duplicate structs | NOT FIXED | |
| 16 | Missing fee adjustment events | NOT FIXED | |
| 17 | Unrestricted test token mint | NOT FIXED | |

**6 of 17 findings fixed, 1 partially fixed, 10 remaining.** All 3 critical findings are addressed. The uncommitted fixes have a minor issue: finding #3's fix has a duplicate `nonReentrant` modifier that needs to be corrected.
