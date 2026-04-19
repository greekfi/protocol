---
title: Deployed Addresses
sidebar_position: 3
---

# Deployed Addresses

:::info
Addresses are not yet finalized for this refactor. This page will be populated as deployments go live.
:::

## Mainnet (Ethereum)

| Contract | Address |
|----------|---------|
| Factory  | _TBD_ |

## Base

| Contract | Address |
|----------|---------|
| Factory  | _TBD_ |

## Unichain

| Contract | Address |
|----------|---------|
| Factory  | _TBD_ |

## Test networks

| Network  | Factory |
|----------|---------|
| Sepolia  | _TBD_ |
| Foundry (31337) | See `foundry/broadcast/` after running `DeployFullDemo`. |

## Programmatic

Once deployed, you can discover options by listening for the factory's event:

```solidity
event OptionCreated(
    address indexed collateral,
    address indexed consideration,
    uint40 expirationDate,
    uint96 strike,
    bool isPut,
    bool isEuro,
    address oracle,
    address indexed option,
    address coll
);
```

Filter by `collateral` or `consideration` to enumerate all options on a given pair.

The web frontend maintains an indexed list via `useOptionsList` — see `web/core/app/book/hooks/useOptionsList.ts`.
