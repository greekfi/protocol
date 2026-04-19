---
title: Overview
sidebar_position: 1
---

# Fundamentals

An option in Greek is fully-collateralized. 
This means any option created has collateral in the protocol backing that option in the event it gets exercised/settled. 

To enable capital efficiency of that collateral Greek provides the option writer a Collateral Token (CLT) along with the Option Token (OPT). Let's dig into this system.

# Minting Option Tokens

Greek offers a mechanism for someone to write options to receive two tokens, OPT and CLT, in return for  depositing collateral:

```
 deposit collateral
 ^
        │
        ▼
 ┌──────────────┐      ┌──────────────┐
 │    Option    │      │  Collateral  │
 │  (long side) │◀────▶│ (short side) │
 └──────────────┘      └──────────────┘
```

Both tokens are standard ERC20. The **Option** holder has the right to receive collateral; the **Collateral** holder backs that right and keeps the premium / post-expiry residual.

## Invariants

- **1:1 backing** - on mint, the number of Option tokens equals Collateral tokens equals deposited collateral. No inflation.
- **Available collateral equals option supply** - while the option is active. Exercise swaps collateral out in return for consideration in; pair-redeem burns matched pairs 1:1.
- **Collateral conservation at expiry** - total payouts to Option + Collateral holders equal the contract's collateral + consideration balance.
- **Decimals are equal to collateral Decimals** - The option and CollateralToken decimals() is the same as the underlying Collateral. This simplifies every downstream calculation.

## No protocol fees

Mint, exercise, pair-redeem, and post-expiry claim are 1:1 — what you put in is what comes out. Revenue is earned at the trading layer (market-maker spread, vault yield).

## Up next

- [Mint & collateralize](./mint-and-collateralize.md) — the deposit flow.
- [Option & Collateral tokens](./tokens.md) — ERC20 semantics, transfers.
- [Auto-mint / auto-redeem](./auto-mint-redeem.md) — opt-in wallet ergonomics.
- [Exercise](./exercise.md) — calls vs puts, strike encoding, exercising on-chain.
