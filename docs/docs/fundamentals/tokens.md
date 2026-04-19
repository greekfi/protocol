---
title: Option & Collateral Tokens
sidebar_position: 3
---

# Option & Collateral Tokens

Both sides of an option are standard ERC20s, deployed as EIP-1167 clones per option pair. Same decimals as the underlying collateral token.

## Option Token (OPT)

- Minted on deposit, burned on `exercise`, `redeem` (pair), or `claim` (settled).
- Transferable. Standard `approve` / `transferFrom` semantics, plus operator approvals via the factory (see below).
- Expiration-gated: `mint`, `transfer`, `exercise`, pair-`redeem` all revert after expiry. Post-expiry, only `settle` and `claim` work (and only in settled modes).

## Collateral Token (CLT)

- Minted 1:1 with Option on deposit.
- Transferable. Burned on pair-`redeem` (pre-expiry) or `redeem` / `redeemConsideration` (post-expiry).
- No expiration gate — coll holders can unwind pre- or post-expiry depending on path.
- accessed via `Option.coll()`.

## Names & symbols

Auto-generated at deploy time from the option's parameters:

```
OPT-WETH-USDC-3000-2026-06-27      // American call
OPTE-WETH-USDC-3000-2026-06-27     // European call (E for Euro)
CLL-WETH-USDC-3000-2026-06-27      // Collateral side
```

Name format: `<prefix>-<collateralSymbol>-<considerationSymbol>-<strike>-<YYYY-MM-DD>`.

Put options display the human-readable strike (inverse of on-chain storage); see [Exercise → Put example](./exercise.md#put-example).

## Operator approvals

The factory exposes an ERC-1155-style universal approval:

```solidity
// Grant operator transfer rights across ALL options created by this factory
factory.approveOperator(operator, true);
```

When approved, `operator` can call `option.transferFrom(owner, to, amount)` on any option created by that factory without needing individual ERC20 approvals. Used by the `/book` CLOBAMM and other trading venues.

## Transfers

Standard ERC20 `transfer` / `transferFrom` work. If the sender has opted into auto-mint/auto-redeem (see next page), the transfer can additionally mint or burn pairs on the fly.
