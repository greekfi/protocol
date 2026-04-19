---
title: Errors
sidebar_position: 2
---

# Custom Errors

All custom errors defined across the core contracts. Selectors are the first 4 bytes of `keccak256("ErrorName()")`.

## Option

| Error | Meaning |
|-------|---------|
| `ContractExpired`             | Pre-expiry function called after expiration. |
| `ContractNotExpired`          | Post-expiry function called before expiration. |
| `InsufficientBalance`         | Caller doesn't hold enough tokens for the operation. |
| `InvalidValue`                | Zero amount or other invalid input. |
| `InvalidAddress`              | Zero address where one isn't allowed. |
| `LockedContract`              | Contract is paused (`coll.locked == true`). |
| `EuropeanExerciseDisabled`    | `exercise()` called on a European option. |
| `NoOracle`                    | `settle` / `claim` called on an option with no oracle. |

## Collateral

| Error | Meaning |
|-------|---------|
| `ContractNotExpired`          | Redeem/settle called before expiry. |
| `ContractExpired`             | Mint called after expiry. |
| `InsufficientBalance`         | Not enough Collateral tokens to redeem. |
| `InvalidValue`                | Zero amount or invalid init parameters (zero strike, past expiry). |
| `InvalidAddress`              | Zero address in init. |
| `LockedContract`              | Contract paused. |
| `FeeOnTransferNotSupported`   | Collateral balance didn't increase by exactly `amount` after transferFrom. |
| `InsufficientCollateral`      | Not enough collateral in contract to cover operation. |
| `InsufficientConsideration`   | Not enough consideration in contract or caller balance for exercise/redeem. |
| `ArithmeticOverflow`          | Amount exceeds `type(uint160).max` (Permit2 cap). |
| `NoOracle`                    | Settle called on non-oracle option. |
| `NotSettled`                  | Post-settlement view called before settlement. |
| `EuropeanExerciseDisabled`    | Exercise or redeemConsideration called in Euro mode. |

## Factory

| Error | Meaning |
|-------|---------|
| `BlocklistedToken`            | Collateral or consideration is on the blocklist. |
| `InvalidAddress`              | Zero address where disallowed. |
| `InvalidTokens`               | Collateral == consideration. |
| `InsufficientAllowance`       | Factory allowance not set or exhausted. |
| `EuropeanRequiresOracle`      | `isEuro=true` but `oracleSource == 0`. |
| `UnsupportedOracleSource`     | `oracleSource` is neither a valid `IPriceOracle` nor a Uniswap v3 pool. |

## UniV3Oracle

| Error | Meaning |
|-------|---------|
| `PoolTokenMismatch`           | Pool's token0/token1 don't match the option's collateral/consideration. |
| `NotExpired`                  | Settle called before option expiry. |
| `AlreadySettled`              | (internal) defensive check on re-settle. |
| `NotSettled`                  | `price()` called before settlement. |
| `WindowTooLong`               | TWAP window + post-expiry delay overflows uint32. |

See each source file for precise conditions that trigger each error.
