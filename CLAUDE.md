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
│   ├── YieldVault.sol       # Operator-run ERC-7540 async vault (Bebop RFQ demo)
│   ├── CLOBAMM.sol          # Named-maker on-chain CLOB (tick-based, FIFO)
│   ├── NuAMMv2.sol          # Pro-rata pooled order book (tick-based, shares+accumulator)
│   ├── BatchMinter.sol      # Batch mint helper
│   ├── ShakyToken.sol       # Test tokens (ShakyToken + StableToken)
│   ├── OptionUtils.sol      # Shared helpers
│   ├── libraries/           # TickMath, CustomRevert (vendored from Uniswap v4)
│   ├── mocks/               # MockERC20 (configurable decimals) for tests + demo
│   └── interfaces/          # IOption, IRedemption, IOptionFactory, IPermit2, etc.
├── test/            # Forge tests (16 files)
├── script/          # Deploy + demo scripts
│   ├── DeployOp.s.sol           # Core deploy (factory, vaults, CLOBAMM)
│   ├── DeployFullDemo.s.sol     # Full demo: 4 underlyings × 3 strikes × 4 expiries × call+put = 96 options
│   ├── DeployBaseDemo.s.sol     # Forked Base demo with WETH/USDC/WBTC/AAVE/UNI
│   ├── DeployBookDemo.s.sol     # CLOBAMM book setup (create option + enableOptionSupport)
│   ├── DeployVaults.s.sol       # Deploy YieldVaults for WETH + USDC
│   ├── PopulateBook.s.sol       # Seed single book with liquidity
│   ├── PopulateVariedBooks.s.sol # Seed varied liquidity per option
│   ├── PopulateAllBooks.s.sol   # Seed uniform liquidity across all options
│   ├── AddTokens.s.sol          # Add new underlyings (AAVE, UNI) to existing deploy
│   ├── FixVaults.s.sol          # Setup factory approvals + operator permissions
│   ├── FundMaker.s.sol          # Fund + approve maker for Bebop
│   └── DeployHelpers.s.sol      # Scaffold-ETH broadcast modifier (patched for forge 1.6+)
├── future/          # Parked: Uniswap v4 hook stack (OpHook, HookVault, OptionPricer,
│                   #   BlackScholes, Constants*). Not built by default. See future/README.md.
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
# Local dev (fresh anvil)
make chain                  # Start local Anvil
yarn deploy                 # Deploy to local network

# Local dev (forked Base — needed for Bebop + real token decimals)
anvil --fork-url https://mainnet.base.org --chain-id 31337
forge script script/DeployFullDemo.s.sol --broadcast --rpc-url http://localhost:8545 \
    --account scaffold-eth-default --password localhost --legacy

# Build & test
forge build
forge test
forge test --match-path test/Option.t.sol
forge test --match-test testExercise
forge test -vvv             # Verbose debugging
forge test --gas-report
forge fmt                   # Format Solidity

# ABI generation (writes to ../web/abi/)
node scripts-js/generateTsAbis.js
# Then sync to standalone web repo:
cp web/abi/chains/foundry.ts ../web/abi/chains/foundry.ts
cp web/abi/deployedContracts.ts ../web/abi/deployedContracts.ts

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

### CLOBAMM.sol — Named-Maker CLOB (primary trading venue)
On-chain order book for options (and any token pair). Makers deposit once, quote at ticks across pairs — balance shared, not fragmented per level. FIFO within level. Tick-based pricing (`1.0001^tick`, ±443,636 range, 1 bip resolution). Bitmap of active ticks (256/word, CLZ opcode). Transient-storage reentrancy lock. No events on quote/cancel (gas savings). `_tickToPrice` uses `Math.mulDiv` for full tick range (no overflow at extreme ticks like USDC/WETH pairs).

**Option integration** (`isOption=true`): checks maker's collateral balance on quote (not option balance), tracks `levelIsOption[lid]`, fills deduct from collateral. `enableOptionSupport(optionToken)` is a permissionless one-time setup that approves factory to pull collateral + opts the book into auto-mint/redeem. On fill, `_transferOut` calls `Option.transfer` which auto-mints options from the book's pooled collateral.

**Key functions**: `deposit`, `withdraw`, `quote`, `cancel`, `requote`, `swap` (market order), `getBook` (view), `getPositions` (maker's open levels).

### NuAMMv2.sol — Pro-rata Pooled Order Book (alt venue)
Similar tick-based model to CLOBAMM, but pooled: tokens locked per level, pro-rata fills within a level, lazy accumulator-based settlement. Anonymous makers. Has matching `enableOptionSupport`. Kept as an alternative venue.

### YieldVault.sol — Operator-Managed Vault
ERC-7540 async-redeem vault for the demo flow. Operator can `execute(target, calldata)` to route trades (e.g., call Bebop `swapSingle` as `msg.sender == vault`). `addOption(option, spender)` whitelists + approves. `redeemExpired()` sweeps post-expiry collateral. `setupFactoryApproval()` sets ERC20 + factory internal allowances. `approveToken(token, spender, amount)` for Bebop or other settlement contracts. No pricing on-chain — RFQ-driven.

### Other Contracts
- **BatchMinter.sol** — Batch mint helper for creating multiple options in one tx.

### Parked (foundry/future/)
The Uniswap v4 hook stack is parked and not built by default:
- **OpHook.sol** — v4 hook (`BaseHook`), delegates pricing + settlement to `HookVault`.
- **HookVault.sol** — ERC4626 vault backing OpHook; auto-mint + v3 SwapRouter02 cash↔coll.
- **OptionPricer.sol** — Black-Scholes + v3 TWAP + smile + inventory spread.
- **BlackScholes.sol** — int256-internal pricing math, WAD fixed-point.
- **ConstantsBase/Mainnet/Unichain.sol** — Uniswap v4 addresses per chain.
- **DeployUpgradeable.s.sol** — Factory + hook deployer (with HookMiner).

See `foundry/future/README.md` for how to bring them back into an active build.

### Ownership
```
OptionFactory (owner: deployer, immutable)
  └→ creates clones:
     Option (owner: user) ←→ Redemption (owner: Option contract)
```

## Key Design Details

**Key invariant**: `available_collateral == total_option_supply` — holds across all operations (mint, exercise, pair redeem, consideration redeem).

**Rounding policy**: round UP when collecting (exercise via `toNeededConsideration`), round DOWN when distributing (payouts via `toConsideration`). This ensures protocol solvency — dust stays in the contract.

**Strike encoding**: Always 18 decimals internally, passed as `uint96` in `createOption()`. Independent of token decimals — decimal normalization happens in Redemption's conversion functions.
- Call: consideration per collateral (e.g., 3000e18 = $3000 USDC per WETH)
- Put: collateral per consideration, inverted (e.g., `1e36 / 3000e18` ≈ 0.000333e18)
- Chainlink settlement comparison: `uint256 spot = uint256(chainlinkPrice) * 1e10; bool itm = spot > strike;` (both 18 dec)

**Decimal normalization**:
```solidity
toConsideration(amount) = mulDiv(amount, strike * 10^consDecimals, 10^18 * 10^collDecimals)           // rounds DOWN
toNeededConsideration(amount) = mulDiv(amount, strike * 10^consDecimals, 10^18 * 10^collDecimals, Ceil) // rounds UP
```

**No protocol fees**: Mint/exercise/redeem are 1:1. Protocol is "free like WETH wrapping." Revenue is earned at the vault layer via the bid/ask spread on `HookVault` (plus inventory-based spread widening) or CLOBAMM maker spreads.

**Clone pattern**: Template contracts deployed once, then `Clones.clone()` for each option. `initializer` modifier prevents re-init.

**Centralized transfers**: All token moves go through `factory.transferFrom()` — single approval point, only callable by registered Redemption contracts.

**Auto-mint/redeem**: Opt-in per account via `factory.enableAutoMintRedeem(true)`. Auto-mint on transfer: if sender balance < amount, factory pulls the deficit in collateral from sender, mints, then transfers. Auto-redeem on receive: factory burns matched Option/Redemption pairs and returns collateral.

**Inventory-based spread** (HookVault): `halfSpread = baseSpreadBps/2 + inventorySkewFactor * abs(netInventory) / totalAssets`. Vault widens its ask when short inventory builds, encourages buybacks.

**CLOBAMM tick math**: `price = 1.0001^tick`. Computed via `Math.mulDiv(sqrtP, sqrtP, 1<<96)` then `Math.mulDiv(ratio, 1e18, 1<<96)` to avoid overflow across the full ±443,636 tick range. Mixed-decimal pairs (e.g. USDC 6dec / WETH 18dec) produce ticks in the -200k range — this is normal.

**CLOBAMM market vs limit orders**: `swap()` pulls tokens directly from taker's wallet (needs ERC20 approval to book). `quote()` checks maker's in-book balance (needs prior `deposit()`). The frontend auto-approves and auto-deposits as needed.

## Demo Setup (Forked Base)

Full demo with real-world decimals on a Base fork:

```bash
# Start forked anvil
anvil --fork-url https://mainnet.base.org --chain-id 31337

# Deploy everything: tokens, factory, CLOBAMM, 96 options, seeded liquidity
forge script script/DeployFullDemo.s.sol --broadcast --rpc-url http://localhost:8545 \
    --account scaffold-eth-default --password localhost --legacy

# Regenerate ABIs + sync to web repo
node scripts-js/generateTsAbis.js
cp web/abi/chains/foundry.ts ../../web/abi/chains/foundry.ts
cp web/abi/deployedContracts.ts ../../web/abi/deployedContracts.ts

# Fund a user address
curl -X POST -H "Content-Type: application/json" \
    --data '{"jsonrpc":"2.0","method":"anvil_setBalance","params":["0xYOUR_ADDR","0x56BC75E2D63100000"],"id":1}' \
    http://localhost:8545

# Deploy vaults (separate from CLOBAMM)
forge script script/DeployVaults.s.sol --broadcast --rpc-url http://localhost:8545 \
    --account scaffold-eth-default --password localhost --legacy \
    --sig "run(address,address,address)" <factory> <weth> <usdc>
```

**DeployFullDemo creates:**
- 5 MockERC20 tokens: WETH(18), USDC(6), WBTC(8), AAVE(18), UNI(18)
- OptionFactory + CLOBAMM
- 96 options: 4 underlyings × 3 strikes × 4 expiries (7d, 14d, 30d, 90d) × call + put
- Each option seeded with 3 ask levels + 2 bid levels of varied liquidity

**Token funding on fork**: `MockERC20.mint()` works freely. Real USDC on Base fork cannot be funded via `deal()` or `vm.store` (proxy storage layout). Use MockERC20 instead.

**forge 1.6+ compatibility**: `DeployHelpers.s.sol` patched to remove `try this.X()` calls (banned by forge 1.6). Chain name defaults to "Anvil" for chainId 31337.

## Frontend (/book page)

The web repo has a `/book` page for the CLOBAMM order book:

```
web/core/app/book/
├── page.tsx                    # Main page: token selector + options chain + book + order form
├── layout.tsx                  # Providers wrapper
├── components/
│   ├── BookOptionsGrid.tsx     # Strike × expiry × call/put chain (like /trade) with on-chain bid/ask
│   ├── BookDisplay.tsx         # Order book: size (with depth bars), price, %spot columns
│   ├── OrderForm.tsx           # Market/limit toggle, buy/sell, auto-approve + auto-deposit
│   ├── MyOrders.tsx            # Open maker positions with cancel buttons
│   ├── Balances.tsx            # In-book + wallet balances, deposit/withdraw
│   ├── OptionHeader.tsx        # Asset, type, strike, expiration, countdown, spot price
│   ├── OptionSelector.tsx      # Tab selector (hidden when ≤1 option)
│   └── Portfolio.tsx           # Fixed bottom-right card showing option positions
├── hooks/
│   ├── useBook.ts              # getBook reads + user balances (works without wallet)
│   ├── useBookWrites.ts        # deposit, withdraw, quote, cancel, swap (smart approval)
│   ├── useBookPrices.ts        # Batch best-bid/ask per option (reads decimals on-chain)
│   ├── useMyOrders.ts          # Cross-references getPositions with getBook to resolve orders
│   ├── useOptionsList.ts       # Reads OptionCreated events from factory (dynamic, not static)
│   └── useSpotPrices.ts        # DeFiLlama prices (WETH, WBTC, AAVE, UNI via CoinGecko IDs)
├── data/
│   └── options.ts              # Static fallback + firstChainWithOptions for network switching
└── lib/
    └── ticks.ts                # priceToTick, tickToPrice, formatPrice (decimal-aware)
```

**Key UX decisions:**
- Book visible without wallet connection (public getBook reads)
- OrderForm always rendered; submit disabled with "Connect Wallet" label when disconnected
- Market orders: auto-approve token to CLOBAMM (checks allowance first, approves 10x to avoid repeated approvals)
- Limit orders: auto-approve + auto-deposit if in-book balance insufficient
- Options discovered dynamically from `OptionCreated` events (getLogs from `currentBlock - 5000` to handle forked chain RPC limits)
- Token list discovered from option events (reads `symbol()` + `decimals()` on-chain), not hardcoded
- Spot prices from DeFiLlama `coins.llama.fi/prices/current/coingecko:ethereum,...` — refreshes every 30s
- Depth bars: cumulative, widest at spread, contained within Size column
- %Spot column: `price / spotPrice * 100`

## Oracle Strategy

For settlement pricing (especially European-style options):

- **Primary: Chainlink** — free to read, industry standard (Aave V4 exclusive oracle). USD-denominated feeds with 8 decimals. Available on Base for ETH/USD, BTC/USD, AAVE/USD, UNI/USD.
- **Fallback: Uniswap V3 TWAP** — already wired in OptionPricer.
- **Cross-asset pricing**: derive from two USD feeds (e.g., `ETH/USD ÷ USDC/USD`). This is what Aave, Compound, GMX, Synthetix all do. No direct pair feeds needed.
- **Strike comparison**: `uint256 spot = uint256(chainlinkPrice) * 1e10; bool itm = spot > strike;` — both 18-decimal, direct compare.

## Testing

16 test files in `foundry/test/`. Key file is `Option.t.sol`:
- Fork testing on Base mainnet via `vm.createSelectFork("https://mainnet.base.org", 43189435)`
- Two approval patterns: Permit2 (`t1` modifier) and standard ERC20 (`t2`)
- Mock tokens: `StableToken` (6 decimals), `ShakyToken` (18 decimals), `MockERC20` (configurable decimals)
- CLOBAMM option integration tests: `CLOBAMMOption.t.sol` (3 tests — quote→swap with auto-mint, withdraw trims, drained maker)
- NuAMMv2 option integration tests: `NuAMMv2Option.t.sol` (2 tests — quote→swap, cancel refunds)
- Other: `FactorySecurityTest`, `FeeOnTransfer`, `GasAnalysis`, `GasBreakdown`, `CloneGas`, `OpHook`, `OptionPrice`, `StrikeTest`, `YieldVault`, `CLOBAMM` (13), `NuAMMv2` (22), `QuoteGas` (3)

## Security

- `ReentrancyGuardTransient` (EIP-1153 transient storage) on Option, Redemption, OptionFactory
- CLOBAMM + NuAMMv2: transient-storage reentrancy lock via raw TSTORE/TLOAD
- Checks-Effects-Interactions pattern
- Custom modifiers: `validAmount`, `validAddress`, `sufficientBalance`, `sufficientCollateral`, `sufficientConsideration`, `notLocked`, `notExpired`
- Emergency pause via `locked` flag
- Fee-on-transfer token detection (balance check on mint) and blocklist
- Permit2 compatibility (uint160 amount checks in Redemption)
- Rounding: `Math.mulDiv` with `Math.Rounding.Ceil` for collections, floor for payouts
- HookVault swap callback: only trusted `swapPool` can invoke `uniswapV3SwapCallback` (mitigates spoofing)
- CLOBAMM sweep bug fixed: `makers[i-1]` captured into local before `_removeMakerFromLevel` (prevents OOB on single-maker drain and wrong-maker removal in multi-maker swap-and-pop)

## Dependencies

- OpenZeppelin Contracts (ERC20, Ownable, ReentrancyGuardTransient, SafeERC20, Clones, Math)
- Foundry (forge, anvil, cast)
- Uniswap v4 hooks, v3-core, v2-core, universal-router
- Permit2 interfaces

## Config

- `foundry.toml`: Compiler settings (`via_ir = true`, solc 0.8.33, evm `osaka`), RPC endpoints, Etherscan API keys, `[lint] exclude_lints`
- `.env`: Private keys, API keys (never commit)
- `remappings.txt`: Import path mappings

## Naming

- Contracts: PascalCase (`Option`, `Redemption`, `OptionFactory`)
- Functions: camelCase (`mint`, `exercise`, `toConsideration`)
- Internal functions: trailing underscore (`mint_`, `redeem_`)
- State variables: camelCase (`collateral`, `expirationDate`)
