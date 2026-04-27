# `exerciseFor` Batch Gas Test — Plan

Goal: measure gas consumption for post-expiry auto-exercise flows across Base (8453), Arbitrum (42161), and Ethereum mainnet (1). Pairs with the settlement-design discussion: if we add `exerciseFor` + a flash-keeper periphery contract, how much does a 100-holder batch actually cost to settle?

## Scenarios

| ID | Scenario | What it measures |
|----|----------|------------------|
| A | `exercise_single` | Baseline: 1 holder calls `exercise` directly (current contract behavior) |
| B | `exerciseFor_batch_100` | Keeper calls `exerciseFor` for 100 holders in one tx — no flash loan, keeper has USDC |
| C | `flashExerciseAndSwap_100` | Full flow: Balancer flash WETH → Uniswap swap → exerciseFor × 100 → repay → pull-style USDC payouts |

Chains are all fork-tested via `vm.createFork(rpcUrl)`. Same bytecode on all three — gas is deterministic per-opcode. What differs is **$-cost** = `gasUsed × gasPrice × ETH/USD`.

## New code (all additive; no existing contract modified)

1. **`foundry/contracts/Option.sol`** — add `exerciseFor(holder, amount, recipient)`:
   - Permissionless post-expiry.
   - Gated on the existing `settled` + ITM check (`priceSettled > strike` for calls; inverted for puts).
   - Pulls USDC from `msg.sender` (the keeper), sends WETH to `recipient`.
   - Optional per-holder `optOut` flag skipped for v1.
   - Signature:
     ```solidity
     function exerciseFor(address holder, uint256 amount, address recipient) external;
     ```

2. **`foundry/contracts/periphery/FlashExerciseKeeper.sol`** — new periphery contract:
   - Uses Balancer Vault `flashLoan` (0 fee on Base, Arbitrum, mainnet).
   - Calls Uniswap v3 `exactInputSingle` on the WETH/USDC 500 pool.
   - Loops `exerciseFor(holder, amount, address(this))` for each holder.
   - Tracks payouts in `mapping(address => uint256) owed` (pull-style).
   - Claim: `withdraw()` sends `owed[msg.sender]` USDC.
   - Keeper fee: `feeBps × intrinsic` per holder, accrued to `keeperOwed[keeper]`.

3. **`foundry/test/ExerciseForGas.t.sol`** — one test file, forks each chain:
   - `setUp()` reads `vm.envString("CHAIN")` → picks the right RPC + Balancer/Uniswap addresses.
   - Deploys Factory + Option/Collateral templates onto the fork.
   - Creates an ITM call option (WETH collateral, USDC consideration).
   - Mints option tokens to N test holders (uses `vm.deal` + mocked auto-mint for speed).
   - Advances time past expiry + settles the oracle.
   - Runs each scenario inside `uint256 g = gasleft(); ...; console.log(g - gasleft());`.

## Chain-specific config

| Chain | Balancer Vault | Uniswap v3 Factory | WETH/USDC 500 pool | USDC | WETH |
|-------|----------------|--------------------|--------------------|------|------|
| Mainnet | 0xBA12222222228d8Ba445958a75a0704d566BF2C8 | 0x1F98431c8aD98523631AE4a59f267346ea31F984 | 0x88e6A0c2dDD26FEEb64F039a2c41296FcB3f5640 | 0xA0b8...eB48 | 0xC02a...6Cc2 |
| Arbitrum | 0xBA12222222228d8Ba445958a75a0704d566BF2C8 | 0x1F98431c8aD98523631AE4a59f267346ea31F984 | 0xC6962004f452bE9203591991D15f6b388e09E8D0 | 0xaf88...5831 | 0x82aF...Bab1 |
| Base | 0xBA12222222228d8Ba445958a75a0704d566BF2C8 | 0x33128a8fC17869897dcE68Ed026d694621f6FDfD | 0xd0b53D9277642d899DF5C87A3966A349A798F224 | 0x8335...2913 | 0x4200...0006 |

(Balancer Vault deployed at the same address via CREATE2 on all three.)

## Run commands

```bash
cd foundry

CHAIN=mainnet MAINNET_RPC=$MAINNET_RPC \
  forge test --match-path test/ExerciseForGas.t.sol -vv --gas-report

CHAIN=arbitrum ARB_RPC=$ARB_RPC \
  forge test --match-path test/ExerciseForGas.t.sol -vv --gas-report

CHAIN=base BASE_RPC=$BASE_RPC \
  forge test --match-path test/ExerciseForGas.t.sol -vv --gas-report
```

## Expected output format

```
Scenario          Gas       L1 $      Arb $     Base $
--------------- --------- --------- --------- ---------
A (single)       ~120k     $7        $0.005    $0.03
B (batch 100)    ~9M       $540      $0.30     $2.00
C (flash 100)    ~12M      $720      $0.40     $2.50
```

(Numbers estimated; real figures come from the test run.)

Pricing assumptions for the $ columns: mainnet 20 gwei / ETH = $2400; Arbitrum 0.01 gwei; Base 0.1 gwei. These go into a small Python / bash helper that reads the `gasUsed` from `forge`'s JSON output and multiplies.

## Known caveats

- Public Arbitrum RPC rate-limits during long fork runs; may need your Alchemy/Infura key. The test guards with `vm.envOr("ARB_RPC", "https://arb1.arbitrum.io/rpc")`.
- Uniswap v3 WETH/USDC 500 has deep liquidity on all three chains. If slippage on a 100-holder aggregate WETH swap matters, the test can split into smaller swaps — but for gas-cost measurement we hit the pool once.
- Base's L1 data cost for tx calldata is *not* reflected in `gasUsed`; it's charged separately. For a realistic $ estimate on Base/Arbitrum, add `calldata_bytes × l1_gas_price × 16 / 1e9` to the execution cost.
- Fork tests require `via_ir = true` which is already set in `foundry.toml`. Long compile; cache will warm after first run.

## Branch

`feat/exercise-for-gas` branched off `origin/main`. Separate from the audit branch so the two are independently mergeable.

## Deliverables

- The three new files above
- A `results.md` under `audit/` with the measured gas per scenario per chain and a $-cost table
- Forge's `--gas-report` output committed for reproducibility

## Open questions before executing

- Batch size — 100 reasonable, or do you want me to also measure 50, 500?
- Balancer flash vs Aave flash — Balancer is 0-fee; Aave 0.09%. Balancer unless you have a reason to prefer Aave.
- Keeper fee model — percent-of-intrinsic (25 bps default) or flat per-holder? Percent is what my plan uses.
- Ethereum mainnet is expensive regardless; still include it in the runs for reference?
