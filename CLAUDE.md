# CLAUDE.md

## Project Overview

Options protocol implementing a dual-token system where both long (Option) and short (Redemption) positions are fully transferable ERC20 tokens. Supports any ERC20 token pairs as collateral/consideration.

The **web app and market maker** live in the `web/` submodule (greekfi/web). This repo is smart contracts only.

## Repo Structure

```
foundry/
├── contracts/       # Solidity source
│   ├── Option.sol           # Long position ERC20
│   ├── Redemption.sol       # Short position ERC20
│   ├── OptionFactory.sol    # Factory (immutable, EIP-1167 clones)
│   ├── OpHook.sol           # Uniswap v4 hook (routes swaps to HookVault)
│   ├── HookVault.sol        # ERC4626 vault backing OpHook (auto-mint, cash↔collateral swap)
│   ├── YieldVault.sol       # Operator-run ERC-7540 async vault (Bebop RFQ demo)
│   ├── OptionPricer.sol     # Pricing engine (BlackScholes + TWAP + inventory spread)
│   ├── BlackScholes.sol     # Pricing math (int256 internal)
│   ├── CLOBAMM.sol          # Named-maker on-chain CLOB (tick-based, FIFO)
│   ├── NuAMMv2.sol          # Pro-rata pooled order book (tick-based, shares+accumulator)
│   ├── BatchMinter.sol      # Batch mint helper
│   ├── ShakyToken.sol       # Test tokens (ShakyToken + StableToken)
│   ├── OptionUtils.sol      # Shared helpers
│   ├── libraries/           # TickMath, CustomRevert (vendored from Uniswap v4)
│   ├── mocks/               # MockERC20 for tests
│   └── interfaces/          # IOption, IRedemption, IOptionFactory, IPermit2, etc.
├── test/            # Forge tests (11 files)
├── script/          # Deploy scripts
├── scripts-js/      # JS helpers (deploy, keystore, ABI gen)
├── lib/             # Git submodule deps (OZ, forge-std, uniswap)
├── foundry.toml     # Compiler config, RPC endpoints, etherscan keys
├── remappings.txt   # Import path mappings
├── Makefile         # chain, deploy, verify targets
└── package.json     # JS deps for deploy scripts
web/                 # Submodule → greekfi/web (frontend + market maker)
```

## Commands

All commands run from `foundry/`:

```bash
# Local dev
make chain                  # Start local Anvil
yarn deploy                 # Deploy to local network
yarn deploy --network base  # Deploy to Base (or unichain, sepolia, etc.)

# Build & test
forge build
forge test
forge test --match-path test/Option.t.sol
forge test --match-test testExercise
forge test -vvv             # Verbose debugging
forge test --gas-report
forge fmt                   # Format Solidity

# Manual deployment
forge script script/Deploy.s.sol:Deploy --broadcast --rpc-url $RPC_URL
cast send $FACTORY "createOption(address,address,uint40,uint96,bool)" ...
```

## Core Contracts

### OptionFactory.sol
Immutable factory (`Ownable`, `ReentrancyGuardTransient`) that deploys Option + Redemption pairs using EIP-1167 minimal proxy clones. Not upgradeable — eliminates the rug vector from owner-controlled implementation swaps (users approve tokens to the factory). Manages token blocklist, centralized `transferFrom()` for all collateral/consideration transfers, ERC-1155-style universal operator approvals (`setApprovalForAll`), and opt-in auto-mint/redeem (`enableAutoMintRedeem`). **No protocol fees** — mint/exercise/redeem are 1:1. Revenue model lives in the vault layer (bid/ask spread).

### Option.sol — Long Position
ERC20 (`Initializable`, `ReentrancyGuardTransient`) representing the right to exercise. Key functions: `mint(amount)`, `exercise(amount)`, `redeem(amount)`. Opt-in auto-settling transfers: auto-mint if sender balance < amount, auto-redeem matched Redemption pairs on receive. Both require the sender/recipient to have called `factory.enableAutoMintRedeem(true)`.

### Redemption.sol — Short Position
ERC20 (`Initializable`, `ReentrancyGuardTransient`) representing the obligation side. Holds all collateral, receives consideration on exercise. Two conversion functions: `toConsideration()` (rounds DOWN, for payouts) and `toNeededConsideration()` (rounds UP, for exercise collections). After expiration, holders have two redemption paths: `redeem()` for pro-rata collateral+consideration, or `redeemConsideration()` for consideration at strike price. Has `sweep(holders[])` for batch post-expiry redemption.

### HookVault.sol — AMM-Style Vault
ERC4626 vault backing `OpHook`. Passive collateral holder with four core functions: `price()` (delegates to `OptionPricer`), `sellOptions()` (vault auto-mints via transferFrom → recipient), `recordBuyback()` (bookkeeping after auto-redeem), `swap()` (Uniswap v3 SwapRouter02 between cash and collateral). Tracks `netInventory` for inventory-based spread widening. Cash never sits — auto-swapped to/from collateral on every trade.

### OptionPricer.sol — Pricing Engine
Separated pricer contract. Black-Scholes + Uniswap v3 TWAP spot feed + quadratic volatility smile + inventory-based half-spread. Single entry point: `price(option, amount, isBuy, netInventory, totalAssets) → (outputAmount, unitPrice)`. Admin setters for volatility, skew, kurtosis, baseSpreadBps, inventorySkewFactor, TWAP pool.

### YieldVault.sol — Operator-Managed Vault
ERC-7540 async-redeem vault for the demo flow. Operator can `execute(target, calldata)` to route trades (e.g., call Bebop `swapSingle` as `msg.sender == vault`). `addOption(option, spender)` whitelists + approves. `redeemExpired()` sweeps post-expiry collateral. No pricing on-chain — RFQ-driven.

### CLOBAMM.sol — Named-Maker CLOB (primary trading venue)
On-chain order book for options (and any token pair). Makers deposit once, quote at ticks across pairs — balance shared, not fragmented per level. FIFO within level. Tick-based pricing (`1.0001^tick`, ±443,636 range, 1 bip resolution). Bitmap of active ticks (256/word, CLZ opcode). Transient-storage reentrancy lock. No events on quote/cancel. `isOption=true` integrates with Greek.fi options: checks collateral balance on quote, mint-on-transfer delivers option tokens on fill. Daily repricing on Base ≈ $11/day at 10s cadence.

### NuAMMv2.sol — Pro-rata Pooled Order Book (alt venue)
Similar tick-based model to CLOBAMM, but pooled: tokens locked per level, pro-rata fills within a level, lazy accumulator-based settlement. Anonymous makers. Kept as an alternative venue — CLOBAMM is primary.

### Other Contracts
- **OpHook.sol** — Uniswap v4 hook (`BaseHook`, `ReentrancyGuard`, `Pausable`). Pure router — delegates pricing + settlement to `HookVault`. Permit2 integration for direct `swapForOption`.
- **BlackScholes.sol** — int256-internal pricing math, WAD fixed-point
- **BatchMinter.sol** — Batch mint helper for creating multiple options in one tx

### Ownership
```
OptionFactory (owner: deployer, immutable)
  └→ creates clones:
     Option (owner: user) ←→ Redemption (owner: Option contract)
```

## Key Design Details

**Key invariant**: `available_collateral == total_option_supply` — holds across all operations (mint, exercise, pair redeem, consideration redeem).

**Rounding policy**: round UP when collecting (exercise via `toNeededConsideration`), round DOWN when distributing (payouts via `toConsideration`). This ensures protocol solvency — dust stays in the contract.

**Strike encoding**: 18 decimals internally, passed as `uint96` in `createOption()`.
- Call: USDC per WETH (e.g., 2000e18)
- Put: WETH per USDC (e.g., 0.0005e18) — inverted from calls

**Decimal normalization**:
```solidity
toConsideration(amount) = mulDiv(amount, strike * 10^consDecimals, 10^18 * 10^collDecimals)           // rounds DOWN
toNeededConsideration(amount) = mulDiv(amount, strike * 10^consDecimals, 10^18 * 10^collDecimals, Ceil) // rounds UP
```

**No protocol fees**: Mint/exercise/redeem are 1:1. Protocol is "free like WETH wrapping." Revenue is earned at the vault layer via the bid/ask spread on `HookVault` (plus inventory-based spread widening).

**Clone pattern**: Template contracts deployed once, then `Clones.clone()` for each option. `initializer` modifier prevents re-init.

**Centralized transfers**: All token moves go through `factory.transferFrom()` — single approval point, only callable by registered Redemption contracts.

**Auto-mint/redeem**: Opt-in per account via `factory.enableAutoMintRedeem(true)`. Auto-mint on transfer: if sender balance < amount, factory pulls the deficit in collateral from sender, mints, then transfers. Auto-redeem on receive: factory burns matched Option/Redemption pairs and returns collateral.

**Inventory-based spread** (HookVault): `halfSpread = baseSpreadBps/2 + inventorySkewFactor * abs(netInventory) / totalAssets`. Vault widens its ask when short inventory builds, encourages buybacks.

## Testing

14 test files in `foundry/test/`. Key file is `Option.t.sol`:
- Fork testing on Base mainnet via `vm.createSelectFork("https://mainnet.base.org", 43189435)`
- Two approval patterns: Permit2 (`t1` modifier) and standard ERC20 (`t2`)
- Mock tokens: `StableToken` (6 decimals), `ShakyToken` (18 decimals), `MockERC20` (configurable decimals, for CLOBAMM/NuAMMv2)
- Other test files: `FactorySecurityTest`, `FeeOnTransfer`, `GasAnalysis`, `GasBreakdown`, `CloneGas`, `OpHook`, `OptionPrice`, `StrikeTest`, `YieldVault`, `CLOBAMM` (13 tests), `NuAMMv2` (22 tests), `QuoteGas` (3 tests)

## Security

- `ReentrancyGuardTransient` (EIP-1153 transient storage) on Option, Redemption, OptionFactory
- Checks-Effects-Interactions pattern
- Custom modifiers: `validAmount`, `validAddress`, `sufficientBalance`, `sufficientCollateral`, `sufficientConsideration`, `notLocked`, `notExpired`
- Emergency pause via `locked` flag
- Fee-on-transfer token detection (balance check on mint) and blocklist
- Permit2 compatibility (uint160 amount checks in Redemption)
- Rounding: `Math.mulDiv` with `Math.Rounding.Ceil` for collections, floor for payouts
- HookVault swap callback: only trusted `swapPool` can invoke `uniswapV3SwapCallback` (mitigates spoofing)

## Dependencies

- OpenZeppelin Contracts (ERC20, Ownable, ReentrancyGuardTransient, SafeERC20, Clones, Math)
- Foundry (forge, anvil, cast)
- Uniswap v4 hooks, v3-core, v2-core, universal-router
- Permit2 interfaces

## Config

- `foundry.toml`: Compiler settings (`via_ir = true`, solc 0.8.33), RPC endpoints, Etherscan API keys
- `.env`: Private keys, API keys (never commit)
- `remappings.txt`: Import path mappings

## Naming

- Contracts: PascalCase (`Option`, `Redemption`, `OptionFactory`)
- Functions: camelCase (`mint`, `exercise`, `toConsideration`)
- Internal functions: trailing underscore (`mint_`, `redeem_`)
- State variables: camelCase (`collateral`, `expirationDate`)
