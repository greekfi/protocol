---
title: Contracts
sidebar_position: 1
---

# Contracts

Quick index. Full ABIs and natspec live alongside the source in `foundry/contracts/`.

## Core

| Contract | Purpose | File |
|----------|---------|------|
| `Option`     | Long-side ERC20. `mint`, `exercise`, `redeem`, `settle`, `claim`, transfers. | `contracts/Option.sol` |
| `Collateral` | Short-side ERC20. Holds collateral, handles exercise flow, oracle settlement. | `contracts/Collateral.sol` |
| `Factory`    | Clones Option + Collateral pairs, single approval point, operator registry. | `contracts/Factory.sol` |

## Oracles

| Contract | Purpose | File |
|----------|---------|------|
| `IPriceOracle` | Oracle interface (18-dec consPerColl). | `contracts/oracles/IPriceOracle.sol` |
| `UniV3Oracle`  | TWAP wrapper for Uniswap v3 pools. | `contracts/oracles/UniV3Oracle.sol` |

## Trading venues

| Contract | Purpose | File |
|----------|---------|------|
| `CLOBAMM`    | Named-maker on-chain CLOB. Balance shared across pairs, FIFO per level. | `contracts/CLOBAMM.sol` |
| `NuAMMv2`    | Pro-rata pooled order book, anonymous makers. | `contracts/NuAMMv2.sol` |
| `HookVault`  | Uniswap v4 hook-backed ERC4626 vault, inventory spread. | `contracts/HookVault.sol` |
| `OpHook`     | Uniswap v4 hook that routes swaps through `HookVault`. | `contracts/OpHook.sol` |

## Vaults

| Contract | Purpose | File |
|----------|---------|------|
| `YieldVault` | Operator-run ERC4626, ERC-7540 async redeems, EIP-1271 signatures for Bebop. | `contracts/YieldVault.sol` |

## Pricing

| Contract | Purpose | File |
|----------|---------|------|
| `OptionPricer` | BS + TWAP + smile + inventory (on-chain quote engine for hook). | `contracts/OptionPricer.sol` |
| `BlackScholes` | Fixed-point BS primitives (int256 internal, WAD). | `contracts/BlackScholes.sol` |

## Interfaces

| Interface | Purpose | File |
|-----------|---------|------|
| `IOption`     | `Option.sol` surface. | `contracts/interfaces/IOption.sol` |
| `ICollateral` | `Collateral.sol` surface. | `contracts/interfaces/ICollateral.sol` |
| `IFactory`    | `Factory.sol` surface + `CreateParams`. | `contracts/interfaces/IFactory.sol` |

## Conventions

- **All contracts use EIP-1167 clones** for per-option instances (`Option`, `Collateral`, `UniV3Oracle`).
- **Storage is packed** where possible: `expirationDate (uint40) + flags (bool) + decimals (uint8)` all fit in one slot.
- **Reentrancy** is guarded with `ReentrancyGuardTransient` (EIP-1153).
- **Rounding policy**: floor on all payouts, ceiling on all collections. Dust stays in protocol.
