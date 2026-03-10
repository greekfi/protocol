# Security Audit — Option.sol, Redemption.sol, OptionFactory.sol

**Date:** 2026-03-10
**Scope:** Core contracts only (Option, Redemption, OptionFactory). No OpHook, OptionPrice, OptionPoolVault, BatchMinter.

---

## 1. Anyone can force-close another user's short position at any time

**Redemption.sol:335** — `redeemConsideration(address account, uint256 amount)`

Public, no `msg.sender == account` check, no expiration requirement. Anyone can call `redeemConsideration(victim, amount)` to burn the victim's Redemption tokens and send them consideration at the current strike conversion rate.

Pre-expiration, the victim may not want their short closed — they're waiting for the option to expire worthless. The attacker doesn't profit directly, but this enables griefing and forced liquidation at unfavorable timing.

**Attack:**
```
1. Alice mints 100 options → holds 99 Option + 99 Redemption (short position)
2. Bob calls redeemConsideration(alice, 99)
3. Alice's 99 Redemption tokens are burned, she receives consideration
4. Alice's short position is gone — she can no longer benefit from expiry
```

**Fix:** Remove the `account` parameter. Only allow `msg.sender` to redeem their own tokens.

---

## 2. Sending Option tokens to a Redemption holder burns their tokens without consent

**Option.sol:495-498, 531-534**

Both `transfer()` and `transferFrom()` auto-redeem when the recipient holds Redemption tokens:
```solidity
balance = redemption.balanceOf(to);
if (balance > 0) {
    redeem_(to, min(balance, amount));
}
```

Anyone can force-close someone's short position by sending them 1 Option token. For a DEX pool or vault holding Redemption tokens, this destroys the pool's position entirely.

**Attack:**
```
1. Alice holds 1000 Redemption tokens (short position worth 1000 collateral)
2. Bob mints 1 Option token, transfers it to Alice
3. Auto-redeem burns 1 of Alice's Redemption tokens + the 1 Option token
4. Alice's position is reduced without her consent
5. Repeat to fully close Alice's position
```

**Fix:** Make auto-redeem opt-in. Add a per-address `allowAutoRedeem` flag that defaults to false.

---

## 3. First-redeemer advantage — collateral vs consideration is a race

**Redemption.sol:299-315** — `_redeem()`

Post-expiration when both collateral and consideration exist (partial exercise scenario), the waterfall gives collateral to whoever redeems first, consideration to everyone else:
```solidity
uint256 balance = collateral.balanceOf(address(this)) - fees;
uint256 collateralToSend = amount <= balance ? amount : balance;
```

If collateral has appreciated relative to consideration, early redeemers extract more value. `sweep(address[])` is worse — the array order is caller-controlled, so the caller puts their own address first.

**Attack:**
```
1. Option partially exercised: 500 of 1000 collateral exchanged for consideration
2. Post-expiry: 500 collateral + consideration in contract, 990 Redemption tokens outstanding
3. MEV bot front-runs and redeems first → gets all 500 collateral
4. Remaining 490 Redemption holders get only consideration (potentially worth less)
```

**Fix:** Pro-rata distribution. Each redeemer receives `(amount / totalSupply) * collateralBalance` collateral AND `(amount / totalSupply) * considerationBalance` consideration simultaneously.

---

## 4. `claimFees()` CEI violation — transfer before state update

**Redemption.sol:418-421**

```solidity
function claimFees() public onlyOwner nonReentrant {
    collateral.safeTransfer(address(_factory), fees);
    fees = 0;  // state updated AFTER external call
}
```

During the transfer, `fees` is stale. `_redeem()` reads `collateral.balanceOf(address(this)) - fees` — stale `fees` inflates available collateral. The reentrancy guards make exploitation difficult today (requires re-entering through Option → `_redeemPair` which has no `nonReentrant`), but this is fragile. With hook-bearing collateral (ERC777, ERC1363), a callback during the transfer could exploit the stale state.

**Fix:**
```solidity
uint256 f = fees;
fees = 0;
collateral.safeTransfer(address(_factory), f);
```

---

## 5. `_redeemPair()` has no reentrancy guard

**Redemption.sol:287**

```solidity
function _redeemPair(address account, uint256 amount) public notExpired notLocked onlyOwner {
    _redeem(account, amount);
}
```

`onlyOwner` restricts to the Option contract, but Redemption's transient reentrancy slot is never locked on this path. Option's slot IS locked (its caller has `nonReentrant`), but each clone has independent transient storage. During `_redeem()` → `collateral.safeTransfer()`, a callback can re-enter Redemption through its non-guarded functions. Combined with #4 (stale fees), this is the reentrancy vector.

**Fix:** Add `nonReentrant` to `_redeemPair()`.

---

## 6. Zero-consideration exercise extracts free collateral

**Redemption.sol:366-383, 451-453**

`toConsideration()` uses `Math.mulDiv` which rounds down:
```solidity
Math.mulDiv(amount, strike * (10 ** consDecimals), (10 ** STRIKE_DECIMALS) * (10 ** collDecimals))
```

For small amounts with decimal mismatch (e.g., 1 wei of 18-decimal collateral, strike 2000e18, 6-decimal consideration): `toConsideration(1) = 0`. Exercise pays 0 consideration, receives 1 wei collateral. No check that `consAmount > 0`.

Gas makes this unprofitable for standard pairs, but it's a protocol correctness bug.

**Fix:** Add `if (consAmount == 0) revert InvalidValue();` in `exercise()`. Consider rounding up with `Math.Rounding.Ceil`.

---

## 7. `transfer()` auto-mints — violates ERC20 and drains collateral

**Option.sol:523-526**

```solidity
uint256 balance = balanceOf(msg.sender);
if (balance < amount) {
    mint_(msg.sender, amount - balance);
}
```

Instead of reverting on insufficient balance (ERC20 standard), `transfer()` silently pulls collateral from the sender and mints. Any protocol interacting with Option tokens via standard `transfer()` (DEXs, routers, aggregators) can have collateral drained unexpectedly.

**Note:** Marked as by-design for UX. The trade-off is that Option tokens are NOT safe for standard ERC20 integrations. Any contract that calls `option.transfer()` on behalf of a user (router, aggregator, vault) will silently mint and pull collateral.

---

## 8. Post-expiration transfer behavior is inconsistent

**Option.sol:515-535, 479-499**

`transfer()` and `transferFrom()` call `redeem_()` which has `notExpired`. After expiration:
- Transfer to recipient **with** Redemption tokens → **reverts**
- Transfer to recipient **without** Redemption tokens → **succeeds**

If the intent is "options are worthless post-expiration, block all transfers," then `notExpired` should be on `transfer`/`transferFrom` directly. Current behavior is confusing — whether a transfer succeeds depends on the recipient's Redemption balance, which the sender can't predict.

**Fix:** Add `notExpired` modifier to `transfer()` and `transferFrom()`.

---

## 9. `renounceOwnership()` + `lock()` = permanent fund lock

**Option.sol** (inherits Ownable)

If the option owner calls `lock()` then `renounceOwnership()`:
- `locked = true`, no one can call `unlock()` (`onlyOwner`, owner is `address(0)`)
- All transfers, mints, exercises, and redeems permanently revert
- Collateral is locked forever

This is also possible through a single malicious owner action.

**Fix:** Override `renounceOwnership()` to revert.

---

## 10. Template contracts don't disable initializers

**Option.sol:101, Redemption.sol:157**

Neither template constructor calls `_disableInitializers()`. Anyone can call `init()` on the deployed templates, gaining ownership. Clones have independent storage so existing options are unaffected, but tokens accidentally sent to templates can be stolen by whoever initializes them.

**Fix:** Add `_disableInitializers()` to both constructors.

---

## 11. `Option.init()` doesn't validate `fee <= MAXFEE`

**Option.sol:115-121**

```solidity
function init(address redemption_, address owner, uint64 fee_) public initializer {
    ...
    fee = fee_;  // no MAXFEE check
}
```

The factory currently passes a valid fee, but defense-in-depth is missing. If the factory is compromised via UUPS upgrade, or if a clone is initialized outside the factory, fee could be set to 100%+, causing underflow in `amount - ((amount * fee) / 1e18)`.

**Fix:** Add `if (fee_ > MAXFEE) revert InvalidValue();`

---

## 12. Consideration fee-on-transfer not checked during exercise

**Redemption.sol:366-383**

`mint()` has a balance-before/after check for collateral, but `exercise()` does not check the consideration token. If a fee-on-transfer token bypasses the blocklist, Redemption receives less consideration than expected. Post-expiration Redemption holders are underpaid.

**Fix:** Add balance-before/after check for consideration in `exercise()`.

---

## 13. `_redeem()` uses `balanceOf()` not internal tracking

**Redemption.sol:300**

```solidity
uint256 balance = collateral.balanceOf(address(this)) - fees;
```

Live balance means:
- Direct token transfers to Redemption inflate available collateral (harmless to protocol, gifts to redeemers)
- Negative rebasing tokens cause `balanceOf < fees` → underflow revert, permanently bricking redemption
- Any external mechanism that reduces balance (permit-based pulls, upgradeable token with admin drain) causes insolvency

**Fix:** Document that rebasing tokens are unsupported. Consider internal balance tracking for robustness.

---

## 14. Factory `approve()` emits no event

**OptionFactory.sol:207-209**

```solidity
function approve(address token, uint256 amount) public {
    if (token == address(0)) revert InvalidAddress();
    _allowances[token][msg.sender] = amount;
}
```

Off-chain systems (frontends, indexers) can't track allowance changes.

**Fix:** Add and emit an `Approval(address indexed token, address indexed owner, uint256 amount)` event.

---

## 15. Factory `claimFees()` and `optionsClaimFees()` have no access control

**OptionFactory.sol:276-301**

Both are public. Anyone can trigger fee transfers. While funds go to `owner()`, this enables:
- Forcing claims at tax-unfavorable times
- DoS if any token in the array reverts on transfer (e.g., paused token)

**Fix:** Add `onlyOwner` or accept as intentional permissionless claiming.

---

## 16. `optionsClaimFees()` accepts unvalidated addresses

**OptionFactory.sol:297-301**

```solidity
function optionsClaimFees(address[] memory options_) public nonReentrant {
    for (uint256 i = 0; i < options_.length; i++) {
        Option(options_[i]).claimFees();
    }
}
```

No `options[addr]` check. Calls `claimFees()` on arbitrary addresses. A malicious contract passed here executes arbitrary code in this context (factory's `nonReentrant` prevents re-entering the factory, but the external call itself is unconstrained).

**Fix:** Add `require(options[options_[i]], "not registered");`

---

## 17. Factory `transferFrom()` uses wrong error for insufficient allowance

**OptionFactory.sol:184**

```solidity
if (currentAllowance < amount) revert InvalidAddress();
```

`InvalidAddress` is wrong — this is an allowance check, not an address check. Misleading for debugging and off-chain error handling.

**Fix:** Add `InsufficientAllowance()` error.

---

## 18. Redemption transfers aren't blocked when locked

**Redemption.sol** — no transfer override

Option overrides `transfer`/`transferFrom` with `notLocked`. Redemption uses default ERC20 transfers with no `locked` check. When the owner locks the contract, Redemption tokens can still be transferred freely. If the intent is an emergency pause, this is a gap. If it's intentional (allow secondary market exit during emergency), it should be documented.

---

## 19. Self-transfer triggers auto-redeem

**Option.sol:515-535**

`transfer(msg.sender, amount)` triggers auto-redeem on yourself if you hold Redemption tokens. Unexpected position closure on what should be a no-op.

**Fix:** Skip auto-redeem when `to == msg.sender`, or add `require(to != msg.sender)`.

---

## 20. Redeemed event emits requested amount, not actual collateral sent

**Redemption.sol:314**

```solidity
emit Redeemed(address(owner()), address(collateral), account, amount);
```

When partially fulfilled with consideration, the event emits `amount` (requested) not `collateralToSend` (actual). Off-chain accounting will be wrong.

**Fix:** Emit `collateralToSend` instead of `amount`.
