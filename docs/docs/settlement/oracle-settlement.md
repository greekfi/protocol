---
title: Oracle Settlement
sidebar_position: 4
---

# Oracle Settlement

When an option has an attached oracle, post-expiry settlement is mechanical: latch the spot, then split the remaining collateral between Option and Collateral holders according to ITM/OTM.

## Three steps

1. **`settle(hint)`** — permissionless, idempotent. Calls the oracle to latch spot and initialize `optionReserveRemaining`.
2. **`option.claim(amount)`** — option holder burns Options, receives ITM payout.
3. **`coll.redeem(amount)`** — collateral holder burns Collateral, receives pro-rata of remaining.

`hint` is oracle-specific: empty bytes for Uniswap TWAP, `abi.encode(roundId)` for Chainlink.

## Math

Given settled spot `S`, strike `K`, option supply at settlement `O`:

### ITM (`S > K`)

```
optionReserve = O × (S - K) / S

option.claim(a)     = a × (S - K) / S           collateral (floor-rounded)
coll.redeem(a)      = pro-rata of:
                        - collateral: (C − liveOptionReserve) × (a / N)
                        - consideration: V × (a / N)
```

Where:
- `C` = current collateral balance
- `V` = current consideration balance (non-zero only if exercised pre-expiry)
- `N` = current Collateral token supply
- `liveOptionReserve` = `optionReserveRemaining` (starts at `O × (S-K)/S`, decrements on each claim)

### OTM (`S ≤ K`)

```
optionReserve = 0

option.claim(a)     = 0   (burns Options, no payout)
coll.redeem(a)      = pro-rata of full remaining balances
```

## Conservation

For any sequence of claim/redeem calls in any order:

```
Σ (option payouts) + Σ (coll payouts, collateral)    = initial collateral balance
                   + Σ (coll payouts, consideration) = initial consideration balance
```

Both sums hold within rounding (floor on all payouts; dust stays in contract).

## Why a reserve?

The reserve decouples claim order from redeem order. Without it:

- If Collateral redeems first, it grabs all remaining collateral.
- Later Option claims have nothing to pay from.

With `optionReserveRemaining`:

- At settle, we snapshot exactly how much collateral option holders are collectively entitled to.
- Collateral redemptions see `collateralBalance - optionReserveRemaining` as their available pool, leaving option holders' share untouched.
- Each claim decrements the reserve, and the claim payout leaves the collateral pool, so the subtraction stays consistent.

## When settle fires automatically

- `option.claim` — if not yet settled, calls `coll.settle("")` before burn.
- `coll.redeem` — if `oracle != 0`, calls `_settle("")` internally.
- `coll.sweep` — same, for batched redemption.

You can also pre-settle manually with `option.settle(hint)` or `coll.settle(hint)`, useful when the oracle requires a non-empty hint (Chainlink roundId).

## Permissionless

`settle` has no access control — anyone can call post-expiry. Bots, keepers, or any interested party can pay the gas to finalize an option. This is by design so a negligent owner can't strand settlement.

## What Option holders lose if they forget

Option holders who never call `claim` leave their ITM share locked in `optionReserveRemaining`. It's recoverable any time — no deadline. But nothing auto-pays it out; you have to call `claim` or `claimFor(holder)`.

`claimFor` is permissionless too, so a bot/keeper can claim on behalf of a holder if incentivized.
