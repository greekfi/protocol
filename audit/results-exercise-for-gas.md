# `exerciseFor` Gas Results

Measured via `forge test --match-path test/ExerciseForGas.t.sol -vv` against live forks of each chain. 100-holder batches. Strike = 1000 USDC/WETH, oracle spot = 3000 USDC/WETH (deeply ITM, amount = 0.01 WETH per holder). Numbers are execution gas from `gasleft()` around the measured call — L1 data cost for Base/Arbitrum is NOT included.

## Execution gas

| Scenario | Base | Arbitrum | Mainnet |
|----------|-----:|---------:|--------:|
| A — single `exerciseFor` | 200,880 | 209,418 | 201,517 |
| B — 100-holder batch (keeper funded) | 4,845,325 | 5,055,625 | 4,909,025 |
| B — per holder | 48,453 | 50,556 | 49,090 |
| C — flash + swap + 100-holder batch | 9,560,490 | 9,772,397 | 9,617,643 |
| C — per holder | 95,604 | 97,723 | 96,176 |

Same bytecode across chains → most of the variance is real ERC20 / Uniswap pool storage access patterns on each fork.

## Dollar cost (illustrative)

Rough figures; user should re-run with current prices.

Assumptions: ETH = $3,500 · mainnet 3 gwei · Arbitrum 0.01 gwei · Base 0.005 gwei.

| Scenario | Base | Arbitrum | Mainnet |
|----------|-----:|---------:|--------:|
| A single | $0.004 | $0.007 | $2.12 |
| B batch×100 | $0.085 | $0.177 | $51.55 |
| C flash+swap×100 | $0.167 | $0.342 | $101.0 |

Base/Arbitrum additionally incur L1 calldata charges (roughly 16 gas × N calldata bytes × L1 gas price); for the 100-holder batch the tx calldata is small (the function sig + one uint per holder inside the contract), so the L1 component is not dominant.

## Observations

- **Per-holder gas settles around ~49k in the pre-funded batch.** The `exerciseFor` cost is dominated by: `_burn` (~20k cold → ~5k warm), the Factory `transferFrom` path (USDC 6-dec ERC20 + allowance decrement), one collateral `safeTransfer`, and the oracle/reserve accounting (`_settle` runs once; `_exerciseForPostExpiry` decrements `optionReserveRemaining`).
- **Flash-loan variant roughly doubles gas** (~95k per holder vs ~49k). The overhead is the Balancer flash envelope + one Uniswap v3 `exactOutputSingle` (with the in-callback `transferFrom` for the swap input). That overhead is amortized over the batch — adding more holders makes the flash variant approach parity in gas/holder with the pre-funded batch.
- **Single-call (A) floor is ~200k gas.** First call post-expiry pays the cold SLOADs + oracle `_settle` + reserve initialization. A second call from the same keeper runs ~70k cheaper because `reserveInitialized` short-circuits `_settle` after the first touch.
- **Flash + swap is only viable if pool spot > strike.** We hit STF on the first run because I'd set strike = 3000 while the Base WETH/USDC pool is sitting at ~2307. Lowered strike to 1000 so the option is ITM against any sane live price on all three forks.

## Economic note on flow

The `exerciseFor` path decrements `optionReserveRemaining` by the residual `amount * (S−K)/S` that the burned option *would* have claimed via the normal `claimFor` path. This keeps short-side redemption math consistent: short holders still see `(collBalance − remainingReserve, consBalance)` as their redeemable pool.

Net balance sheet per holder exercised (strike K, spot S, collateral token C, consideration token Q):
- Long holder: `−1 Option, 0` (token burned, no direct payout — economic value comes from the keeper paying out in USDC off-stream)
- Keeper: `−K·amount Q, +amount C` (buys the option at strike, captures intrinsic above)
- Collateral contract: `+K·amount Q, −amount C, reserve −= amount·(S−K)/S` (still solvent per key invariant)
- Short holders: collectively lose `amount − residual = amount·K/S` C, gain `K·amount Q` — fair at settled spot.

## Reproducibility

```bash
cd foundry
CHAIN=base forge test --match-path test/ExerciseForGas.t.sol -vv
CHAIN=arbitrum forge test --match-path test/ExerciseForGas.t.sol -vv
CHAIN=mainnet forge test --match-path test/ExerciseForGas.t.sol -vv
```

RPCs resolved from the `[rpc_endpoints]` block in `foundry.toml` (public endpoints by default). If those rate-limit, override with an Alchemy/Infura URL in `.env` and patch the rpc alias.
