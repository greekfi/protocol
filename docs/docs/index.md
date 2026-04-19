---
title: Greek
slug: /
sidebar_position: 0
---

# Greek
Greek is a options infrastructure on EVM (Mainnet, Base, Arbitrum). It provides the capability to produce and trade unique, universal ERC20 option tokens for any underlying collateral (and [consideration](./fundamentals/exercise.md)), expiration date and strike price.

Greek has partnered with [Bebop](https://bebop.xyz) to provide [options trades](./trading.md) through their RFQ system with on-chain settlement.

## What the protocol does

Greek provides the ability to create tokens and smart contracts for:
1. European Options with Settlement
2. American Options with Settlement
3. American Options without Settlement 

Every token is ERC20, making it fungible and transferable hence swappable. 

## Where to start

- **[Fundamentals](./fundamentals/overview.md)** — Option Token + Collateral Token; exercise, settlement, collateral redemption; auto-mint/redeem.
- **[Trading](./trading.md)** — RFQ flows via Bebop, buying and shorting, market-makers, market takers.
- **[Settlement](./settlement/overview.md)** — exercise, pair-redeem, oracle settlement, post-expiry paths.
- **[Reference](./reference/contracts.md)** — contracts, errors, deployed addresses.
