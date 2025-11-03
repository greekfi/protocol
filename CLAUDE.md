# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is an **options protocol** built on Scaffold-ETH 2, implementing a dual-token options system where both long (Option) and short (Redemption) positions are fully transferable ERC20 tokens. The protocol supports any ERC20 tokens as collateral or consideration, enabling flexible options trading beyond traditional cash/asset distinctions.

## Development Commands

### Local Development (Three Terminal Setup)
```bash
yarn chain          # Terminal 1: Start local Anvil blockchain
yarn deploy         # Terminal 2: Deploy contracts to local network
yarn start          # Terminal 3: Start Next.js frontend at http://localhost:3000
```

### Smart Contract Development
```bash
yarn compile              # Compile Solidity contracts with Foundry
yarn foundry:test         # Run all Foundry tests
yarn foundry:clean        # Clean build artifacts
yarn format               # Format code (both Solidity and TypeScript)
yarn foundry:lint         # Lint Solidity code
```

### Testing Specific Contracts
```bash
# Run a specific test file
forge test --match-path packages/foundry/test/Option.t.sol

# Run a specific test function
forge test --match-test testExercise

# Run with verbosity for debugging
forge test -vvv

# Run with gas reporting
forge test --gas-report
```

### Account Management
```bash
yarn account              # List available accounts
yarn account:generate     # Generate new keystore account
yarn account:import       # Import existing private key
```

### Deployment to Networks
```bash
yarn deploy --network unichain        # Deploy to Unichain
yarn deploy --network sepolia         # Deploy to Sepolia
yarn deploy:verify --network sepolia  # Deploy and verify on Etherscan
```

### Frontend Development
```bash
yarn next:build           # Build Next.js production bundle
yarn next:check-types     # TypeScript type checking
yarn next:lint            # Lint Next.js code
yarn vercel               # Deploy to Vercel
```

## Architecture Overview

### Core Smart Contracts

The protocol uses a **dual-token options model** with four main contracts:

1. **OptionBase.sol** - Abstract base contract
   - Provides ERC20 functionality, ownership, reentrancy protection
   - Defines core parameters: collateral, consideration, strike, expiration, isPut
   - Implements decimal normalization between tokens with different decimals
   - Key utilities: `toConsideration()` and `toCollateral()` for strike price conversions

2. **Option.sol** - The "long option" (right to buy)
   - Inherits from OptionBase
   - **Owns** the paired Redemption contract
   - Main operations:
     - `mint()`: Creates matched Option + Redemption token pairs (requires collateral deposit)
     - `exercise()`: Burns Option tokens, pays consideration, receives collateral
     - `redeem()`: Burns matched Option + Redemption pairs, returns collateral
   - **Auto-settling transfers**:
     - Transferring more Options than you own → auto-mints the difference
     - Receiving Options while holding Redemption → auto-redeems the minimum

3. **Redemption.sol** - The "short option" (obligation to sell)
   - Inherits from OptionBase
   - Stores collateral and receives consideration on exercise
   - Main operations:
     - `mint()`: Only callable by Option contract
     - `exercise()`: Only callable by Option contract
     - `redeem()`: Callable post-expiration or via Option contract pre-expiration
     - `redeemConsideration()`: Redeem using consideration if collateral depleted
     - `sweep()`: Batch redemption for all holders after expiration
   - **Dual approval system**: Supports both standard ERC20 approvals and Uniswap Permit2

4. **OptionFactory.sol** - Factory for creating option pairs
   - Uses OpenZeppelin's Clones library (EIP-1167) for gas-efficient deployment
   - Deploys minimal proxies pointing to template contracts
   - Maintains registry of all options via custom AddressSet
   - Query options by collateral/consideration pair

### Key Design Patterns

#### Strike Price Encoding
The `strike` is encoded with 18 decimals and includes the exchange ratio plus decimal adjustments:
```solidity
uint256 public constant STRIKE_DECIMALS = 10 ** 18;
// toConsideration = (amount * strike) / STRIKE_DECIMALS
```

#### Permit2 Integration
Redemption contract supports gasless approvals via Uniswap's Permit2:
```solidity
function transferFrom_(address from, address to, IERC20 token, uint256 amount) internal {
    if (token.allowance(from, address(this)) >= amount) {
        token.safeTransferFrom(from, to, amount);  // Standard path
    } else {
        PERMIT2.transferFrom(from, to, uint160(amount), address(token));  // Permit2 path
    }
}
```
Permit2 address: `0x000000000022D473030F116dDEE9F6B43aC78BA3`

#### Clone Pattern for Deployment
OptionFactory creates minimal proxies (~45 gas) instead of full deployments:
- Template contracts deployed once during factory initialization
- Each option pair is a minimal proxy clone
- Contracts use `Initializable` pattern instead of constructors

### Contract Relationships

```
OptionFactory
    ├── Creates Option clone → Option Instance
    └── Creates Redemption clone → Redemption Instance
                                        ↑
                                        │
                                    Owned by
                                        │
                                   Option Instance
```

**Ownership Flow:**
1. Factory creates Redemption with Factory as initial owner
2. Factory creates Option with Factory as initial owner
3. Redemption.setOption() transfers ownership to Option
4. Option.setRedemption() links to Redemption
5. Factory transfers Option ownership to deployer

### Frontend Architecture (Scaffold-ETH 2)

Located in `packages/nextjs/`:
- **Framework**: Next.js with App Router (not Pages Router)
- **Web3 Stack**: RainbowKit + Wagmi + Viem
- **Styling**: Tailwind CSS v4.1.8
- **Contract Hot Reload**: Frontend auto-updates when contracts change

**Key Scaffold-ETH Hooks** (in `packages/nextjs/hooks/scaffold-eth/`):
- `useScaffoldReadContract`: Read contract state
- `useScaffoldWriteContract`: Write to contracts
- `useScaffoldWatchContractEvent`: Watch for events
- `useScaffoldEventHistory`: Query historical events
- `useDeployedContractInfo`: Get deployed contract info

**Key Scaffold-ETH Components** (in `packages/nextjs/components/scaffold-eth/`):
- `<Address>`: Display Ethereum addresses
- `<AddressInput>`: Input field for addresses
- `<Balance>`: Display ETH/USDC balance
- `<EtherInput>`: Number input with ETH/USD conversion

**Contract Interactions:**
Always use Scaffold-ETH hooks, never raw wagmi/viem directly:

```typescript
// Reading
const { data: balance } = useScaffoldReadContract({
  contractName: "Option",
  functionName: "balanceOf",
  args: [address],
});

// Writing
const { writeContractAsync } = useScaffoldWriteContract({ contractName: "Option" });
await writeContractAsync({
  functionName: "mint",
  args: [amount],
});
```

Contract ABIs are auto-generated in `packages/nextjs/contracts/deployedContracts.ts` when you run `yarn deploy`.

## Important Implementation Notes

### Security Considerations
- All state-changing functions use `nonReentrant` modifier
- Checks-Effects-Interactions pattern followed consistently
- Input validation via custom modifiers: `validAmount`, `validAddress`, `sufficientBalance`
- Emergency pause mechanism via `locked` flag (prevents transfers only)

### Testing Approach
Tests in `packages/foundry/test/Option.t.sol`:
- 40+ test cases covering normal operations, edge cases, time-based logic, and multi-user scenarios
- Fork testing on Unichain via `vm.createSelectFork(UNICHAIN_RPC_URL)`
- Two approval patterns tested: Permit2 (modifier `t1`) and standard ERC20 (modifier `t2`)
- Mock tokens: StableToken and ShakyToken

### Compiler Configuration
Uses `via_ir = true` in foundry.toml for IR-based optimization. This enables better gas optimization but increases compilation time.

### Recent Refactoring
Git history shows recent rename:
- `LongOption` → `Option`
- `ShortOption` → `Redemption`

## Development Workflow

1. **Modify contracts** in `packages/foundry/contracts/`
2. **Update deployment scripts** in `packages/foundry/script/` if needed
3. **Run tests** with `yarn foundry:test`
4. **Deploy locally** with `yarn deploy`
5. **Test in UI** at `http://localhost:3000/debug` (Debug Contracts page)
6. **Build custom UI** using Scaffold-ETH components and hooks
7. **Deploy to network** with `yarn deploy --network <network_name>`
8. **Deploy frontend** with `yarn vercel`

## Configuration Files

- `foundry.toml`: Solidity compiler settings, RPC endpoints (20+ networks configured), Etherscan API keys
- `scaffold.config.ts`: Frontend network configuration, target network settings
- `.env`: Private keys, API keys (never commit this file)
- `remappings.txt`: Import path mappings for dependencies

## Key Dependencies

- **OpenZeppelin Contracts v5.3.0**: ERC20, Ownable, ReentrancyGuard, SafeERC20, Clones
- **Foundry**: Solidity development framework (forge, anvil, cast)
- **Next.js**: Frontend framework
- **Permit2**: Uniswap's signature-based approval system
- **Moment-timezone**: Date/time handling for expiration dates

## Naming Conventions

- Contracts use PascalCase: `Option`, `Redemption`, `OptionFactory`
- Functions use camelCase: `mint`, `exercise`, `toConsideration`
- Internal functions end with underscore: `mint_`, `redeem_`, `transferFrom_`
- State variables use camelCase: `collateral`, `consideration`, `expirationDate`
- Public state variables often have explicit getter names with trailing underscore: `redemption_`