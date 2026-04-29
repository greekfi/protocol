# `exerciseFor` Batch Gas Test — Plan

Goal: measure gas consumption for post-expiry auto-exercise flows across Base (8453), Arbitrum (42161), and Ethereum mainnet (1). Pairs with the settlement-design discussion: if we add `exerciseFor` + a flash-keeper periphery contract, how much does a 100-holder batch actually cost to settle?

> Note: the `auto-settlements` branch (formerly `v2-updates`) **already implements** this test as `foundry/test/ExerciseForGas.t.sol` and reports results in `audit/results-exercise-for-gas.md`. Numbers below are from that run.

## Scenarios

| ID | Scenario | What it measures |
|----|----------|------------------|
| A | `exercise_single` | Baseline: 1 holder calls `exercise` directly |
| B | `exerciseFor_batch_100` | Keeper calls `exerciseFor` for 100 holders in one tx — no flash loan |
| C | `flashExerciseAndSwap_100` | Full flow: Balancer flash WETH → Uniswap swap → exerciseFor × 100 → repay → pull-style USDC payouts |

Chains are all fork-tested via `vm.createFork(rpcUrl)`. Same bytecode on all three — gas is deterministic per-opcode. What differs is **$-cost** = `gasUsed × gasPrice × ETH/USD`.

## New code

1. **`foundry/contracts/Option.sol`** — add `exerciseFor(holder, amount, recipient)`:
   - Permissionless post-expiry within the exercise window.
   - Pulls consideration from `msg.sender` (the keeper), sends collateral to `recipient`.

2. **`foundry/contracts/periphery/FlashExerciseKeeper.sol`** — periphery:
   - Uses Balancer Vault `flashLoan` (0 fee on Base, Arbitrum, mainnet).
   - Calls Uniswap v3 `exactInputSingle` on the WETH/USDC 500 pool.
   - Loops `exerciseFor(holder, amount, address(this))` per holder.
   - Tracks payouts in `mapping(address => uint256) owed` (pull-style).
   - Keeper fee: `feeBps × intrinsic` per holder.

3. **`foundry/test/ExerciseForGas.t.sol`** — one test file, forks each chain.

## Chain-specific config

| Chain | Balancer Vault | Uniswap v3 Factory | WETH/USDC 500 pool | USDC | WETH |
|-------|----------------|--------------------|--------------------|------|------|
| Mainnet | 0xBA12222222228d8Ba445958a75a0704d566BF2C8 | 0x1F98431c8aD98523631AE4a59f267346ea31F984 | 0x88e6A0c2dDD26FEEb64F039a2c41296FcB3f5640 | 0xA0b8…eB48 | 0xC02a…6Cc2 |
| Arbitrum | 0xBA12222222228d8Ba445958a75a0704d566BF2C8 | 0x1F98431c8aD98523631AE4a59f267346ea31F984 | 0xC6962004f452bE9203591991D15f6b388e09E8D0 | 0xaf88…5831 | 0x82aF…Bab1 |
| Base | 0xBA12222222228d8Ba445958a75a0704d566BF2C8 | 0x33128a8fC17869897dcE68Ed026d694621f6FDfD | 0xd0b53D9277642d899DF5C87A3966A349A798F224 | 0x8335…2913 | 0x4200…0006 |

## Run commands

```bash
cd foundry
CHAIN=mainnet  MAINNET_RPC=$MAINNET_RPC  forge test --match-path test/ExerciseForGas.t.sol -vv --gas-report
CHAIN=arbitrum ARB_RPC=$ARB_RPC          forge test --match-path test/ExerciseForGas.t.sol -vv --gas-report
CHAIN=base     BASE_RPC=$BASE_RPC        forge test --match-path test/ExerciseForGas.t.sol -vv --gas-report
```

## Live results from `auto-settlements`

Per `audit/results-exercise-for-gas.md` on the `auto-settlements` branch (100-holder batches, deeply ITM):

| Scenario | Base | Arbitrum | Mainnet |
|----------|-----:|---------:|--------:|
| A — single `exerciseFor` | 200,880 | 209,418 | 201,517 |
| B — 100-holder batch (per holder) | 48,453 | 50,556 | 49,090 |
| C — flash + swap (per holder) | 95,604 | 97,723 | 96,176 |

Dollar cost (illustrative — re-run with current prices):

| Scenario | Base | Arbitrum | Mainnet |
|----------|-----:|---------:|--------:|
| A single | $0.004 | $0.007 | $2.12 |
| B batch×100 | $0.085 | $0.177 | $51.55 |
| C flash+swap×100 | $0.167 | $0.342 | $101.0 |

Assumptions: ETH $3,500; mainnet 3 gwei; Arbitrum 0.01 gwei; Base 0.005 gwei.

## Known caveats

- Public Arbitrum RPC rate-limits during long fork runs; need an Alchemy/Infura key.
- Base's L1 data cost is **not** reflected in `gasUsed` — add separately for realistic $ estimates.
- Fork tests require `via_ir = true` (already set in `foundry.toml`).
