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
│   ├── OptionFactory.sol    # Factory (UUPS upgradeable)
│   ├── OpHook.sol           # Uniswap v4 hook
│   ├── OptionPoolVault.sol  # ERC4626 vault
│   ├── OptionPrice.sol      # On-chain pricing (Uniswap v3 TWAP)
│   ├── BatchMinter.sol      # Batch mint helper
│   ├── ShakyToken.sol       # Test tokens (ShakyToken + StableToken)
│   └── interfaces/          # IOption, IRedemption, IOptionFactory, IPermit2, etc.
├── test/            # Forge tests (10 files)
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
Immutable factory (`Ownable`, `ReentrancyGuardTransient`) that deploys Option + Redemption pairs using EIP-1167 minimal proxy clones. Not upgradeable — eliminates the rug vector from owner-controlled implementation swaps (users approve tokens to the factory). Manages token blocklist, centralized `transferFrom()` for all collateral/consideration transfers, ERC-1155-style universal operator approvals (`setApprovalForAll`), and opt-in auto-mint/redeem (`enableAutoMintRedeem`). Fee claiming is permissionless — anyone can trigger the Redemption → Factory → Owner flow. Max fee: 1% (`0.01e18`).

### Option.sol — Long Position
ERC20 (`Initializable`, `ReentrancyGuardTransient`) representing the right to exercise. Key functions: `mint(amount)`, `exercise(amount)`, `redeem(amount)`. Opt-in auto-settling transfers: auto-mint if sender balance < amount (fee-adjusted with ceiling division), auto-redeem matched Redemption pairs on receive. Both require the sender/recipient to have called `factory.enableAutoMintRedeem(true)`.

### Redemption.sol — Short Position
ERC20 (`Initializable`, `ReentrancyGuardTransient`) representing the obligation side. Holds all collateral, receives consideration on exercise. Two conversion functions: `toConsideration()` (rounds DOWN, for payouts) and `toNeededConsideration()` (rounds UP, for exercise collections). After expiration, holders have two redemption paths: `redeem()` for pro-rata collateral+consideration, or `redeemConsideration()` for consideration at strike price. Has `sweep(holders[])` for batch post-expiry redemption.

### Other Contracts
- **OpHook.sol** — Uniswap v4 hook (`BaseHook`, `ReentrancyGuard`, `Pausable`) with Permit2 integration
- **OptionPoolVault.sol** — ERC4626 vault for option pool liquidity
- **OptionPrice.sol** — On-chain option pricing using Uniswap v3 TWAP
- **BatchMinter.sol** — Batch mint helper for creating multiple options in one tx

### Ownership
```
OptionFactory (owner: deployer, immutable)
  └→ creates clones:
     Option (owner: user) ←→ Redemption (owner: Option contract)
```

## Key Design Details

**Key invariant**: `available_collateral == total_option_supply` — holds across all operations (mint, exercise, pair redeem, consideration redeem, fee claim).

**Rounding policy**: round UP when collecting (exercise via `toNeededConsideration`), round DOWN when distributing (payouts via `toConsideration`). This ensures protocol solvency — dust stays in the contract.

**Strike encoding**: 18 decimals internally, passed as `uint96` in `createOption()`.
- Call: USDC per WETH (e.g., 2000e18)
- Put: WETH per USDC (e.g., 0.0005e18) — inverted from calls

**Decimal normalization**:
```solidity
toConsideration(amount) = mulDiv(amount, strike * 10^consDecimals, 10^18 * 10^collDecimals)           // rounds DOWN
toNeededConsideration(amount) = mulDiv(amount, strike * 10^consDecimals, 10^18 * 10^collDecimals, Ceil) // rounds UP
```

**Fee flow**: Fees deducted on mint as collateral, tracked by `Redemption.fees`. Three-hop claim: `Redemption → Factory → Owner`. All fee claim functions are permissionless.

**Clone pattern**: Template contracts deployed once, then `Clones.clone()` for each option. `initializer` modifier prevents re-init.

**Centralized transfers**: All token moves go through `factory.transferFrom()` — single approval point, only callable by registered Redemption contracts.

**Auto-mint/redeem**: Opt-in per account via `factory.enableAutoMintRedeem(true)`. Auto-mint uses ceiling division to ensure fee-adjusted amount covers the transfer deficit.

## Testing

10 test files in `foundry/test/`. Key file is `Option.t.sol`:
- Fork testing on Base mainnet via `vm.createSelectFork("https://mainnet.base.org", 43189435)`
- Two approval patterns: Permit2 (`t1` modifier) and standard ERC20 (`t2`)
- Mock tokens: `StableToken` (6 decimals), `ShakyToken` (18 decimals)
- Additional test files: `FactorySecurityTest`, `FactoryCriticalIssues`, `FeeOnTransfer`, `GasAnalysis`, `GasBreakdown`, `GasErrors`, `CloneGas`, `OpHook`, `OptionPrice`

## Security

- `ReentrancyGuardTransient` (EIP-1153 transient storage) on Option, Redemption, OptionFactory
- Checks-Effects-Interactions pattern
- Custom modifiers: `validAmount`, `validAddress`, `sufficientBalance`, `sufficientCollateral`, `sufficientConsideration`, `notLocked`, `notExpired`
- Emergency pause via `locked` flag
- Fee-on-transfer token detection (balance check on mint) and blocklist
- `sufficientCollateral` modifier subtracts fees to prevent fee collateral from being spent
- Permit2 compatibility (uint160 amount checks in Redemption)
- Rounding: `Math.mulDiv` with `Math.Rounding.Ceil` for collections, floor for payouts

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
