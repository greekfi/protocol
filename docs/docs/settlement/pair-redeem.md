---
title: Pair Redeem
sidebar_position: 3
---

# Pair Redeem

Pair-redeem is the universal "I changed my mind" unwind. You hold both Option and Collateral for the same pair, you burn them together, and you get your collateral back.

```solidity
option.redeem(amount);
```

Works pre-expiry, in every mode (American, European, settled or not).

## Semantics

1. `amount` Option tokens burned from caller.
2. `amount` Collateral tokens burned from caller.
3. `amount` collateral returned to caller.

The caller must hold at least `amount` of both tokens. Otherwise reverts with `InsufficientBalance`.

## Why it always works

Pair-redeem is collateral-neutral. Burning a matched pair is the exact inverse of minting a pair — it doesn't take anything from un-paired holders or change the option/collateral supply relationship for anyone else.

## Post-expiry

Pair-redeem is gated by `notExpired`. Post-expiry, you use:

- `coll.redeem(amount)` — post-expiry unwind. Pays pro-rata or oracle split depending on mode. Does NOT require matched Option tokens.
- `option.claim(amount)` — option-holder ITM payout (settled modes only).

The pair-redeem mechanism is specifically pre-expiry because post-expiry, the terms are different — the option holder has a well-defined ITM or zero payout, and the collateral holder gets the rest. Burning a matched pair post-expiry would short-change one side or the other.

## When is this useful?

- **Market maker unwinding a position** — you're short via auto-mint, you bought back the same amount of options, you burn the matched pair and re-claim collateral.
- **Liquidity provider adjusting exposure** — pair-redeem and re-mint into a different strike/expiry.
- **Auto-redeem on receive** — if you opted into auto-mint/redeem, receiving Options while holding Collateral auto-triggers pair-redeem for matched amounts. See [Auto-mint & auto-redeem](../fundamentals/auto-mint-redeem.md).

## No oracle required

Pair-redeem doesn't care about spot, strike, or expiry state. It's pure collateral conservation: in, out, 1:1. The only way it can fail is if something has corrupted the 1:1 invariant — in which case the contract has bigger problems than your unwind.
