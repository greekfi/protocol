---
title: Mint & Collateralize
sidebar_position: 2
---

# Mint & Collateralize

To open an option position, you deposit collateral through the `Option` contract. The protocol mints an equal amount of `Option` + `Collateral` tokens to your address and holds the collateral in escrow until the option is exercised, pair-redeemed, or settled at expiry.

## Approvals

Users approve the **factory** once, not each option. The factory is the single transfer authority — it's the only contract that pulls your underlying tokens, and it does so only when a registered Collateral contract asks it to.

```solidity
// One-time setup
IERC20(collateral).approve(address(factory), type(uint256).max);
factory.approve(collateral, type(uint256).max);
```

The first line is a standard ERC20 approval to the factory. The second registers the allowance in the factory's internal book, which is what Collateral contracts check on mint.

## Minting

```solidity
// Mint 1 option backed by 1 unit of collateral
option.mint(1e18);

// Or mint to someone else
option.mint(recipient, 1e18);
```

Under the hood:

1. `Option.mint` calls `Collateral.mint(account, amount)`.
2. Collateral calls `factory.transferFrom(account, this, amount, collateralToken)` to pull the deposit.
3. Collateral verifies the balance increased by exactly `amount` (fee-on-transfer tokens are rejected).
4. `Option` and `Collateral` tokens are minted 1:1 to `account`.

After mint, the Collateral contract holds the collateral. Its balance equals the outstanding Option supply.

## Key contracts

- `Option.sol` — public entry point. `mint(amount)`, `mint(to, amount)`.
- `Collateral.sol` — holds escrow, enforces 1:1. Only callable by its paired Option.
- `Factory.sol` — clone factory, allowance registry, blocklist.

See [Reference → Contracts](../reference/contracts.md) for full surface.
