---
title: Overview
sidebar_position: 1
---

# Settlement

How an option ends depends on its mode, which is set at creation and baked in:

| Mode                    | `isEuro` | `oracle`   | Pre-expiry                        | Post-expiry                                           |
|-------------------------|:--------:|:----------:|------------------------------------|--------------------------------------------------------|
| American, non-settled   | false    | `0x0`      | `exercise` + pair-`redeem`         | `redeem` (pro-rata) + `redeemConsideration`           |
| American, settled       | false    | non-zero   | `exercise` + pair-`redeem`         | `redeem` (oracle split) + `redeemConsideration` + `claim` |
| European                | true     | non-zero   | pair-`redeem` only                 | `settle` + `claim` + `redeem` (oracle split)          |

Invalid combo: `isEuro=true, oracle=0` — rejected at creation.

## Always available

Regardless of mode, these are always callable pre-expiry:

- **`mint(amount)`** — open new pairs from collateral.
- **`option.redeem(amount)`** (pair-redeem) — burn matched Option + Collateral, recover collateral. No price lookup; always 1:1. See [Pair redeem](./pair-redeem.md).
- **`transfer` / `transferFrom`** — trade options. Auto-mint / auto-redeem fire if opted in.

## American-specific (pre-expiry)

- **`exercise(amount)`** — burn Options, pay strike × amount in consideration, receive collateral. Reverts in European mode. See [Exercise](../fundamentals/exercise.md).

## Post-expiry

This is where modes diverge.

### Non-settled (American only)

No oracle, so no spot lookup. Collateral holders redeem pro-rata against whatever collateral + consideration is in the contract:

- `redeem(amount)` — pro-rata split of remaining collateral + consideration.
- `redeemConsideration(amount)` — alternative path, takes consideration at strike rate.

### Settled (American or European)

Anyone can call `settle(hint)` post-expiry to latch the oracle price. Then:

- `option.claim(amount)` — option holder burns and receives the ITM payout (`amount × (spot - strike) / spot`).
- `coll.redeem(amount)` — collateral holder takes pro-rata of `(collateralBalance - optionReserve, considerationBalance)` — where `optionReserve` is the un-exercised collateral earmarked for option holders.
- `coll.redeemConsideration(amount)` — still works in American-settled (pulls from consideration pot); meaningless in European (no consideration ever entered).

See [Oracle settlement](./oracle-settlement.md) for the math and conservation proof.

## Permissionless triggers

`settle` and `sweep` (for batching post-expiry redemptions) are **permissionless** — anyone can pay the gas to finalize a contract, including bots. This is deliberate: no stakeholder can block settlement.

## Oracles

Oracles are per-option, pinned to the option's expiration at creation:

- **UniV3Oracle** — TWAP over a configurable window ending at expiry. Ships today.
- **ChainlinkOracle** — planned, uses round-ID hints for precise settlement. See plan doc.

Factory accepts any `IPriceOracle` implementer, plus raw Uniswap v3 pools (deploys the wrapper inline). See [Oracles](./oracles.md).
