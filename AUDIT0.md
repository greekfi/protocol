# Audit Report: Option, Redemption, OptionFactory

## CRITICAL

### 1. Auto-mint in `transfer()` always reverts when `fee > 0`

**File:** `Option.sol:522-548`

When a sender with `autoMintRedeem` enabled tries to transfer more Option tokens than they hold, the auto-mint path mints **fewer tokens than needed** because the fee is deducted from the minted amount, but the transfer still tries to send the full `amount`:

```solidity
uint256 balance = balanceOf(msg.sender);
if (balance < amount) {
    if (!IOptionFactory(factory()).autoMintRedeem(msg.sender)) revert InsufficientBalance();
    mint_(msg.sender, amount - balance);  // mints (amount-balance) * (1 - fee/1e18)
}
success = super.transfer(to, amount);     // tries to send full `amount` → REVERTS
```

After `mint_`, the sender has:
```
balance + (amount - balance) * (1e18 - fee) / 1e18  =  amount - deficit * fee / 1e18
```

This is always **less than `amount`** when `fee > 0` and `deficit > 0`. The `super.transfer` reverts with insufficient balance.

**Fix:** Either mint a fee-adjusted amount (`deficit * 1e18 / (1e18 - fee)`), or transfer only the actual minted amount, or skip fees during auto-mint.

---

## MEDIUM

### 2. Auto-redeem in transfers can revert the entire transfer

**File:** `Option.sol:499-506, 540-547`

Both `transfer()` and `transferFrom()` trigger auto-redeem on the recipient if opted in. The auto-redeem calls `redeem_()` → `redemption._redeemPair()` → `_redeemPairInternal()`. If the Redemption contract lacks enough collateral, the waterfall falls through to `_redeemConsideration()`, which reverts with `InsufficientConsideration` if no exercises have occurred. This **blocks the entire transfer**.

A user who opted into `autoMintRedeem` and holds Redemption tokens can become unable to receive Option tokens via transfer if the Redemption contract has insufficient consideration balance.

**Fix:** Wrap the auto-redeem in a try/catch or limit auto-redeem to the collateral-backed portion.

### 3. Post-expiry pro-rata rounding can leave last redeemer short

**File:** `Redemption.sol:300-316`

In `_redeem()`, `remainder = amount - collateralToSend` is calculated after `Math.mulDiv` rounds `collateralToSend` **down**. This rounds each redeemer's `remainder` **up**, causing each one to claim slightly more consideration than their fair share. Over many redemptions, the last redeemer may not have enough consideration left and the `safeTransfer` reverts.

This is a dust-level issue but could block the final redeemer in extreme edge cases (many small redemptions with unfavorable decimal combinations).

### 4. `Option.claimFees()` has no access control

**File:** `Option.sol:693-695`

```solidity
function claimFees() public nonReentrant {
    redemption.claimFees();
}
```

Anyone can call this, which moves accumulated fees from the Redemption contract to the Factory. While funds aren't stolen (they go to the factory, not the caller), it removes the option owner's ability to control timing of fee collection. A griefing attacker could call this repeatedly, creating unnecessary gas costs for the factory owner who then needs to withdraw from the factory.

### 5. `_redeemPairInternal` waterfall uses `sufficientConsideration` which checks raw consideration balance

**File:** `Redemption.sol:363-374`

`_redeemConsideration()` has a `sufficientConsideration(address(this), collAmount)` modifier, but this converts `collAmount` to consideration using `toConsideration()` and checks the contract's consideration balance. If consideration was partially drained by earlier `redeemConsideration()` calls (allowed both pre and post-expiry at line 353), the waterfall in `_redeemPairInternal` can fail, leaving pre-expiry pair redemptions blocked.

---

## LOW / INFORMATIONAL

### 6. `redeemConsideration()` has no expiry restriction

**File:** `Redemption.sol:353-355`

`redeemConsideration()` can be called both before and after expiry (no `notExpired` or `expired` modifier). Post-expiry, this offers an alternative to the pro-rata `redeem()` — users can cherry-pick whichever path gives them more value. This may not be the intended behavior. If it is intended, it should be documented that post-expiry redemption has two separate paths with different economics.

### 7. Storage gap mismatch with comment

**File:** `OptionFactory.sol:387`

Comment says "Reserves 50 storage slots" but the gap is `uint256[48]`. Should be updated to match.

### 8. No rescue mechanism for tokens sent directly to contracts

If tokens are sent directly to Option or Redemption contracts (not via `mint`/`exercise`), they're stuck forever. For collateral sent directly to Redemption, it inflates `collateral.balanceOf(address(this))` and distorts pro-rata calculations (benefiting redeemers at the sender's expense). Consider adding an owner-only rescue function for non-collateral/consideration tokens.

### 9. Duplicate utility functions

`uint2str`, `strike2str`, `epoch2str`, `isLeapYear`, `min`, `max` are duplicated verbatim in both Option.sol and Redemption.sol. Consider extracting to a shared library to reduce template deployment costs.

### 10. Unused private storage in Option

**File:** `Option.sol:34-35`

`_tokenName` and `_tokenSymbol` are declared but never set in `init()` (only in the constructor for the template). Since `name()` and `symbol()` are overridden with dynamic generation, these waste 2 storage slots on every clone.

### 11. `sufficientCollateral` modifier doesn't account for fees

**File:** `Redemption.sol:131-134`

The modifier checks `collateral.balanceOf(account) < amount` against the raw balance (including fees). While this is not exploitable due to Option supply being bounded by `deposited - fees`, it's semantically incorrect. Using `collateral.balanceOf(account) - fees < amount` would be more precise.

---

## Design Notes (not bugs)

- **Expired Options are worthless and non-transferable**: By design, but users holding both Option+Redemption tokens post-expiry must use the Redemption-side `redeem()` only (pair redeem is blocked by `notExpired`).
- **Dual approval required**: Users must approve both the factory's internal allowance (`factory.approve()`) AND the ERC20 approval (`token.approve(factory)`). Easy to miss.
- **`sweep()` for anyone post-expiry**: Anyone can trigger redemption for any holder. Funds go to the holder, not caller. Safe but could have tax/timing implications for the holder.
- **`Redemption.constructor` ignores all parameters**: By design for clone template pattern.
