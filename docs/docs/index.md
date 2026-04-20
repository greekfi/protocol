---
title: Greek
slug: /
sidebar_position: 0
---

# Greek
Greek is a options infrastructure on EVM (Mainnet, Base, Arbitrum). It provides the capability to produce and trade unique, universal ERC20 option tokens for any underlying collateral (and [consideration](./fundamentals#consideration)), expiration date and strike price.

Greek has partnered with [Bebop](https://bebop.xyz) to provide [options trades](./trading.md) through their RFQ system with on-chain settlement.

## What the protocol does

Greek provides the ability to create tokens and smart contracts for:
1. European Options with Settlement
2. American Options with Settlement
3. American Options without Settlement

Every token is ERC20, making it fungible and transferable hence swappable.

## Where to start

- **[Fundamentals](./fundamentals)** — Option Token + Collateral Token; exercise, settlement, collateral redemption; auto-mint/redeem.
- **[Trading](./trading)** — RFQ flows via Bebop, buying and shorting, market-makers, market takers.
- **[Settlement](./settlement)** — pair-redeem, oracle settlement, post-expiry paths.
- **[API Reference](./reference/api)** — full contract surface, generated from NatSpec.
