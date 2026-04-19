---
title: Auto-Mint & Auto-Redeem
sidebar_position: 4
---

# Auto-Mint & Auto-Redeem

Standard ERC20 transfers assume the sender has tokens and the receiver just credits them. For an options protocol, that's inflexible — a market maker often wants to sell options they haven't minted yet, it would be extremely unscalable to mint 100 variations of options (strikes,expirations).

Similarly, when receiving options to close a position an option writer wants that collateral back atomically.

Greek offers **opt-in** capabilities for both:

- **Auto-mint** — automatically mint options as they are transfered by collateralizing the underlying collateral.
- **Auto-redeem** — receiving options while holding matched Collateral tokens burns the pair and returns collateral.

## Opting in

```solidity
factory.enableAutoMintRedeem(true);
```

By enabling this flag for your wallet, every option in that factory can have auto-mint and auto-redeem.
This is disabled by default. Both directions fire based on the sender's/receiver's opt-in independently.

## Auto-mint: sell-without-minting

```solidity
// Maker hasn't minted yet, but holds collateral.
// Maker opts in, then signs a transfer.
factory.enableAutoMintRedeem(true);

// Taker pulls options via transferFrom
option.transferFrom(maker, taker, 10e18);
```

On the transfer:

1. Maker's option balance is 0, requested amount is 10e18.
2. Since maker opted in, the deficit (`10e18 - 0`) is minted — factory pulls 10e18 collateral from the maker and mints 10e18 Option + 10e18 Collateral to the maker.
3. Then the standard transfer moves the 10e18 Option tokens to the taker.

Net: maker holds 10 Collateral, taker holds 10 Option, collateral is locked in the Collateral contract. Same outcome as `mint` + `transfer`, one tx.

## Auto-redeem: unwind-on-receive

```solidity
// Taker holds 10 Option + 10 Collateral (e.g. from a pair position).
// Taker opts in.
factory.enableAutoMintRedeem(true);

// Any further Option arriving at taker burns matched pairs.
IERC20(option).transfer(taker, 3e18);
```

On receive:

1. Taker's Collateral balance is 10e18, incoming 3e18.
2. Since taker opted in, `min(3e18, 10e18) = 3e18` pairs are burned.
3. 3e18 collateral is released back to taker.

## When it fires

Both transfer entry points apply auto-settling: `transfer(to, amount)` and `transferFrom(from, to, amount)`. Auto-mint checks the **sender's** opt-in flag; auto-redeem checks the **receiver's**. Each side is independent.

Auto-mint and auto-redeem are gated by `notExpired` — after expiry, neither fires and transfers follow normal ERC20 semantics.

## Why this matters

- Market makers using RFQ can commit to a quote without pre-minting, then let the taker's settlement trigger the mint.
- Pair holders can unwind a position just by receiving their matched tokens — no separate `redeem` call needed.
- The CLOBAMM / NuAMMv2 on-chain books rely on this to deliver options from pooled collateral without per-level minting.
