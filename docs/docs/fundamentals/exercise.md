---
title: Exercise
sidebar_position: 4
---

# Exercising an Option

An option is simply a swap of K units of Token A (Consideration) for 1 Token B (Collateral) at any time the option holder wants before exercise.
Typically the swap is performed when the price (A for B) is well above the strike price, K. 

# Collateral

Any asset can be a collateral, as long as it's an ERC20 token and its value does not change because fees on swapping or anything similar. Examples include WETH, WBTC, UNI, AAVE. 

This is pretty standard and straightfoward in the world of options. But the consideration is a different story.

# Consideration

The term consideration is rarely used in the options world because in nearly all options markets, the US Dollar is used as the consideration for every option swap. 
In on-chain finance, we re-introduce the consideration because of two main reasons:
1. There's several tokens that can be used as US Dollar denominations to be the consideration (USDC, USDT, DAI, etc.)
2. We can open this options market to have not only other currencies (Euro, K-Won) but also non country fiat can be used, such as WETH-WBTC can be an option pair as well as WBTC-OIL. 

# Exercising on-chain
An option can easily be exercised on-chain at any time (e.g. block).
Simply call exercise with an amount (X) that you want to exercise:
```
uint256 amountX = 1e18;
IOption option = IOption(optionAddress);
option.exercise(amountX);
```
1. The option is burned
2. X \* Strike of Consideration is transfered to the Option+Collateral Contracts
3. X of Collateral will be transfered to your wallet. 


## Call example

A WETH call at $3,000 strike:

| Role          | Token |
|---------------|-------|
| Collateral    | WETH  |
| Consideration | USDC  |
| Strike        | `3000e18` (USDC per WETH) |

- Minting deposits WETH.
- Exercising pays USDC → gets WETH.
- At expiry (settled), ITM means `spotUSDC/WETH > 3000`.

## Put example

A WETH put at $3,000 strike is just a call written on the swapped pair:

| Role          | Token |
|---------------|-------|
| Collateral    | USDC  |
| Consideration | WETH  |
| Strike        | `1e36 / 3000e18` (WETH per USDC, in 18-dec units) |

- Minting deposits USDC.
- Exercising pays WETH → gets USDC.
- The `isPut` flag on the option is display-only; the contract math is identical to a call.


## Important
- All strike prices are decimal 18 notation
- Firstly, this can only be called in American options.
- European options are not able to be exercised before the expiration date.
- After the expiration date, no exercise is possible - if the option has a settlement price Oracle, then it will automatically exercise but only deliver the amount that is above the strike price at expiration.
