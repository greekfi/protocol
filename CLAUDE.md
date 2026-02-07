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
├── test/            # Forge tests (10 files, 154 test functions)
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
UUPS upgradeable (`Initializable`, `UUPSUpgradeable`, `OwnableUpgradeable`) factory that deploys Option + Redemption pairs using EIP-1167 minimal proxy clones. Manages token blocklist and centralized `transferFrom()` for all collateral/consideration transfers. Max fee: 1% (`0.01e18`).

### Option.sol — Long Position
ERC20 (`Initializable`, `ReentrancyGuardTransient`) representing the right to exercise. Key functions: `mint(amount)`, `exercise(amount)`, `redeem(amount)`. Transfer has auto-settling logic — if recipient holds Redemption tokens, matched pairs auto-redeem.

### Redemption.sol — Short Position
ERC20 (`Initializable`, `ReentrancyGuardTransient`) representing the obligation side. Holds all collateral, receives consideration on exercise. After expiration, holders redeem for their share of collateral (or consideration if collateral depleted). Handles decimal normalization between token pairs. Has `sweep(holders[])` for batch redemption.

### Other Contracts
- **OpHook.sol** — Uniswap v4 hook (`BaseHook`, `ReentrancyGuard`, `Pausable`) with Permit2 integration
- **OptionPoolVault.sol** — ERC4626 vault for option pool liquidity
- **OptionPrice.sol** — On-chain option pricing using Uniswap v3 TWAP
- **BatchMinter.sol** — Batch mint helper for creating multiple options in one tx

### Ownership
```
OptionFactory (owner: deployer, UUPS upgradeable)
  └→ creates clones:
     Option (owner: user) ←→ Redemption (owner: Option contract)
```

## Key Design Details

**Strike encoding**: 18 decimals internally, passed as `uint96` in `createOption()`.
- Call: USDC per WETH (e.g., 2000e18)
- Put: WETH per USDC (e.g., 0.0005e18) — inverted from calls

**Decimal normalization**:
```solidity
toConsideration(amount) = (amount * strike * 10^consDecimals) / (10^18 * 10^collDecimals)
```

**Clone pattern**: Template contracts deployed once, then `Clones.clone()` for each option. `initializer` modifier prevents re-init.

**Centralized transfers**: All token moves go through `factory.transferFrom()` — single point of control, only callable by registered Redemption contracts.

## Testing

10 test files in `foundry/test/` with 154 test functions total. Key file is `Option.t.sol` (46 tests):
- Fork testing on Unichain via `vm.createSelectFork("https://unichain.drpc.org")`
- Two approval patterns: Permit2 (`t1` modifier) and standard ERC20 (`t2`)
- Mock tokens: `StableToken` (6 decimals), `ShakyToken` (18 decimals)
- Additional test files: `FactorySecurityTest`, `FactoryCriticalIssues`, `FeeOnTransfer`, `GasAnalysis`, `GasBreakdown`, `GasErrors`, `CloneGas`, `OpHook`, `OptionPrice`

## Security

- `ReentrancyGuardTransient` (EIP-1153 transient storage) on Option, Redemption, OptionFactory
- Checks-Effects-Interactions pattern
- Custom modifiers: `validAmount`, `validAddress`, `sufficientBalance`, `notLocked`, `notExpired`
- Emergency pause via `locked` flag
- Fee-on-transfer token detection and blocklist
- Permit2 compatibility (uint160 amount checks in Redemption)

## Dependencies

- OpenZeppelin Contracts + Contracts Upgradeable (ERC20, Ownable, UUPS, ReentrancyGuardTransient, SafeERC20, Clones)
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
