# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is an **options protocol** built on Scaffold-ETH 2, implementing a dual-token options system where both long (Option) and short (Redemption) positions are fully transferable ERC20 tokens. The protocol supports any ERC20 tokens as collateral or consideration, enabling flexible options trading beyond traditional cash/asset distinctions.

### What Makes This Protocol Unique

- **Dual ERC20 Tokens**: Both option sides (long and short) are freely tradable ERC20 tokens
- **Any Token Pairs**: Create options between any ERC20 tokens (not limited to ETH/stablecoins)
- **Decimal Normalization**: Handles tokens with different decimals (e.g., USDC has 6, WETH has 18)
- **Gas-Efficient Deployment**: Uses EIP-1167 minimal proxy clones for ~95% gas savings
- **Auto-Settling Transfers**: Smart transfer logic that auto-redeems matched pairs
- **Collateral Backing**: Every option token is 1:1 backed by deposited collateral
- **Post-Expiration Flexibility**: Redemption tokens can be redeemed for collateral or equivalent consideration value

## Development Commands

### Smart Contract Folders
```bash
<Root>/protocol/foundry/contracts
<Root>/protocol/foundry/test
<Root>/protocol/foundry/script
<Root>/protocol/core
```


### React Folders
```bash
<Root>/protocol/core
```

### Local Development (Three Terminal Setup)
```bash
yarn chain          # Terminal 1: Start local Anvil blockchain
yarn deploy         # Terminal 2: Deploy contracts to local network
yarn start          # Terminal 3: Start Next.js frontend at http://localhost:3000
```

### Smart Contract Development
```bash
forge build             # Compile Solidity contracts with Foundry
forge test              # Run all Foundry tests
forge clean             # Clean build artifacts
forge fmt               # Format code (both Solidity and TypeScript)
yarn foundry:lint       # Lint Solidity code
```

### Testing Specific Contracts
```bash
# Run a specific test file
forge test --match-path foundry/test/Option.t.sol

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

The protocol consists of **three main contracts** that work together to create a fully-functional options system:

#### 1. **OptionFactory.sol** - The Factory Contract

**Purpose**: Deploys new option pairs using minimal proxy clones (EIP-1167)

**Key Responsibilities**:
- Stores template contracts for Option and Redemption
- Creates gas-efficient clones (~45 gas vs ~2M gas for full deployment)
- Manages a blocklist for problematic tokens (fee-on-transfer, rebasing)
- Provides centralized token transfer logic for collateral/consideration
- Tracks all deployed Redemption contracts for security

**Key Functions**:
- `createOption()`: Deploys a new Option + Redemption pair
- `createOptions()`: Batch deployment of multiple option pairs
- `transferFrom()`: Centralized token transfer (only callable by Redemption contracts)
- `blockToken()` / `unblockToken()`: Manage token blocklist

**Storage**:
```solidity
address public redemptionClone;  // Template Redemption contract
address public optionClone;      // Template Option contract
uint64 public fee;               // Protocol fee (max 1%)
mapping(address => bool) public blocklist;  // Blocked tokens
mapping(address => bool) private redemptions;  // Deployed Redemption contracts
```

---

#### 2. **Option.sol** - The Long Position (Call/Right Side)

**Purpose**: Represents the right to exercise the option (buy/sell at strike price)

**Token Economics**:
- ERC20 token representing long option position
- Minted when user deposits collateral
- Burnable through exercise or redemption
- Freely tradable/transferable

**Key Responsibilities**:
- Owns and coordinates with paired Redemption contract
- Manages option lifecycle (mint, exercise, redeem)
- Implements auto-settling transfer logic
- Delegates all collateral/consideration operations to Redemption

**Key Functions**:
- `mint(amount)`: Deposits collateral, creates Option + Redemption token pairs
- `exercise(amount)`: Burns Option tokens, pays consideration, receives collateral
- `redeem(amount)`: Burns matched Option + Redemption pairs (pre-expiration only)
- `transfer(to, amount)`: ERC20 transfer with auto-redeem if recipient holds Redemptions

**Auto-Settling Transfer Logic**:
```solidity
// When you transfer Options:
transfer(recipient, 100) {
    1. Transfer 100 Option tokens to recipient
    2. Check if recipient has Redemption tokens
    3. If yes, auto-redeem min(redemptionBalance, 100)
    4. Recipient gets collateral back, both tokens burned
}
```

**Storage**:
```solidity
Redemption public redemption;  // Paired Redemption contract
uint64 public fee;             // Protocol fee
```

All option parameters (collateral, consideration, strike, expiration) are delegated to Redemption contract.

---

#### 3. **Redemption.sol** - The Short Position (Put/Obligation Side)

**Purpose**: Represents the obligation side of the option, holds collateral, receives consideration

**Token Economics**:
- ERC20 token representing short option position
- Always minted in pairs with Option tokens
- Redeemable for collateral after expiration
- Can be redeemed for consideration if collateral is depleted

**Key Responsibilities**:
- Stores ALL collateral for the option
- Receives consideration when options are exercised
- Manages decimal normalization between tokens
- Handles redemption after expiration
- Accumulates protocol fees

**Key Functions**:
- `mint(account, amount)`: Pulls collateral, mints Redemption tokens (only callable by Option)
- `exercise(account, amount, caller)`: Pulls consideration, sends collateral (only callable by Option)
- `redeem(amount)`: Burns tokens, returns collateral (post-expiration only)
- `redeemConsideration(amount)`: Burns tokens, returns equivalent consideration value
- `sweep(holders[])`: Batch redemption for multiple holders after expiration

**Storage**:
```solidity
uint256 public fees;                 // Accumulated protocol fees
uint256 public strike;               // Strike price (18 decimal encoding)
IERC20 public collateral;            // Token used as collateral
IERC20 public consideration;         // Token used for exercise payment
IFactory public _factory;            // Factory contract reference
uint64 public fee;                   // Protocol fee percentage
uint40 public expirationDate;        // Unix timestamp expiration
bool public isPut;                   // Put vs Call
bool public locked;                  // Emergency lock flag
uint8 consDecimals;                  // Consideration token decimals
uint8 collDecimals;                  // Collateral token decimals
```

**Decimal Normalization**:
The contract handles tokens with different decimals (e.g., WETH=18, USDC=6) using these conversion functions:
```solidity
toConsideration(collateralAmount) → considerationAmount
toCollateral(considerationAmount) → collateralAmount
```

---

### How the Protocol Works (Complete Lifecycle)

#### **Phase 1: Factory Deployment**

When the protocol is first deployed:

```solidity
1. Deploy template contracts:
   - Deploy Redemption template (never used directly)
   - Deploy Option template (never used directly)

2. Deploy OptionFactory:
   OptionFactory factory = new OptionFactory(
       redemptionTemplate,
       optionTemplate,
       fee  // e.g., 0.001e18 = 0.1%
   );
```

#### **Phase 2: Creating an Option**

User calls `factory.createOption()` to create a new option pair:

```solidity
// Example: Create WETH call option with USDC strike
address optionAddress = factory.createOption(
    collateral: 0xWETH,      // Collateral token (what you buy)
    consideration: 0xUSDC,   // Payment token (what you pay)
    expiration: 1735689600,  // Jan 1, 2025
    strike: 2000e18,         // $2000 (18 decimal encoding)
    isPut: false             // Call option
);

// Factory does:
1. Clones Redemption template → redemption_clone
2. Clones Option template → option_clone
3. Initializes Redemption with all parameters
4. Initializes Option with redemption reference
5. Sets Option as owner of Redemption
6. Transfers Option ownership to msg.sender
7. Registers redemption_clone in redemptions mapping
8. Returns option_clone address
```

After this, you have:
- **Option Contract**: At `option_clone` address, owned by user
- **Redemption Contract**: At `redemption_clone` address, owned by Option contract

#### **Phase 3: Minting Option Tokens**

User deposits collateral to create option tokens:

```solidity
// User approves collateral token
WETH.approve(optionAddress, 10 ether);

// User calls mint
Option(optionAddress).mint(10 ether);

// What happens:
1. Option.mint() calls Redemption.mint()
2. Redemption.mint():
   - Calls factory.transferFrom() to pull 10 WETH from user
   - Verifies exactly 10 WETH received (anti fee-on-transfer)
   - Calculates fee: 10 * 0.001 = 0.01 WETH
   - Stores 0.01 WETH in fees
   - Mints 9.99 Redemption tokens to user
3. Option.mint():
   - Mints 9.99 Option tokens to user

// User now has:
- 9.99 Option tokens (can exercise)
- 9.99 Redemption tokens (collateral claim)
- Redemption contract holds 10 WETH (9.99 backing + 0.01 fees)
```

#### **Phase 4A: Exercising Options**

Before expiration, option holder can exercise:

```solidity
// Option holder approves consideration
USDC.approve(optionAddress, 20000e6); // $20,000 USDC (6 decimals)

// Holder exercises 5 options
Option(optionAddress).exercise(5 ether);

// What happens:
1. Option.exercise():
   - Burns 5 Option tokens from holder
   - Calls Redemption.exercise(holder, 5 ether, holder)
2. Redemption.exercise():
   - Calculates consideration needed: toConsideration(5) = 10,000 USDC
   - Calls factory.transferFrom() to pull 10,000 USDC from holder
   - Sends 5 WETH collateral to holder
   - Redemption contract now holds:
     * 4.99 WETH (remaining collateral)
     * 10,000 USDC (from exercise)
     * 0.01 WETH (fees)

// Holder now has:
- 4.99 Option tokens (if they had 9.99)
- 5 WETH (received from exercise)
- 9.99 Redemption tokens (unchanged)
```

#### **Phase 4B: Redeeming Matched Pairs**

Before expiration, users can burn matched pairs to get collateral back:

```solidity
// User has 9.99 Option + 9.99 Redemption tokens
Option(optionAddress).redeem(5 ether);

// What happens:
1. Option.redeem():
   - Burns 5 Option tokens from user
   - Calls Redemption._redeemPair(user, 5)
2. Redemption._redeemPair():
   - Burns 5 Redemption tokens from user
   - Sends 5 WETH collateral to user

// User now has:
- 4.99 Option tokens
- 4.99 Redemption tokens
- 5 WETH (received from redemption)
```

#### **Phase 5: After Expiration**

After expiration date passes, Redemption holders can redeem:

```solidity
// User holds 4.99 Redemption tokens after expiration
Redemption(redemptionAddress).redeem(4.99 ether);

// What happens:
1. Check: block.timestamp >= expirationDate ✓
2. Burns 4.99 Redemption tokens
3. Checks collateral available:
   - If 4.99 WETH available: sends 4.99 WETH
   - If only 2 WETH available: sends 2 WETH + equivalent USDC
4. User receives their share of remaining assets
```

**Consideration Redemption** (if collateral depleted):
```solidity
// Redemption contract has:
// - 0 WETH (all exercised)
// - 10,000 USDC (from exercises)

Redemption(redemptionAddress).redeemConsideration(5 ether);

// What happens:
1. Burns 5 Redemption tokens
2. Calculates USDC value: toConsideration(5) = $10,000 USDC
3. Sends 10,000 USDC to user
```

#### **Phase 6: Sweep (Batch Redemption)**

After expiration, anyone can sweep multiple holders:

```solidity
address[] memory holders = [alice, bob, charlie];
Redemption(redemptionAddress).sweep(holders);

// Redeems all Redemption tokens for each holder in one tx
```

---

### Contract Ownership & Access Control

```
┌─────────────────┐
│ OptionFactory   │ ← Owned by: Deployer
│                 │
│ Creates ↓       │
└─────────────────┘

┌─────────────────┐      ┌─────────────────────┐
│ Option          │◄─────┤ Redemption          │
│                 │ Owns │                     │
│ Owner: User     │      │ Owner: Option       │
└─────────────────┘      │ Factory ref         │
                         └─────────────────────┘
```

**Access Control Rules**:
- **Factory**: Can call `transferFrom()` on behalf of Redemption contracts
- **Option**: Can call `mint()`, `exercise()`, `_redeemPair()`, `lock()`, `unlock()` on Redemption
- **Anyone**: Can call `redeem()` on Redemption after expiration
- **Users**: Can call `mint()`, `exercise()`, `redeem()` on Option anytime

### Key Design Patterns

#### Strike Price Encoding
The `strike` is encoded with 18 decimals to handle any token pair, regardless of their native decimals:

```solidity
uint8 public constant STRIKE_DECIMALS = 18;

// Example: 1 WETH = 2000 USDC
// Strike = 2000 * 10^18 = 2000000000000000000000

// Convert collateral amount to consideration:
toConsideration(amount) = (amount * strike * 10^consDecimals) / (10^STRIKE_DECIMALS * 10^collDecimals)

// Example with 5 WETH → USDC:
// = (5 * 10^18 * 2000 * 10^18 * 10^6) / (10^18 * 10^18)
// = 10000 * 10^6 = 10,000 USDC
```

This allows the protocol to handle any token pair combinations (WETH/USDC, USDC/DAI, etc.) with perfect precision.

#### Clone Pattern for Gas Efficiency (EIP-1167)

Instead of deploying full contracts for each option (which costs ~2M gas), the factory uses minimal proxy clones:

```solidity
// Full deployment cost: ~2,000,000 gas
Option newOption = new Option(...);

// Clone deployment cost: ~45 gas
address optionClone = Clones.clone(templateAddress);
```

**How it works**:
1. Template contracts deployed once during factory initialization
2. Each clone is a tiny proxy that delegatecalls to the template
3. Clones use `initialize()` instead of `constructor()` (OpenZeppelin Initializable pattern)
4. ~99% gas savings per option deployment

**Security Note**: The `initializer` modifier ensures `init()` can only be called once, preventing re-initialization attacks.

#### Centralized Token Transfer (Factory Pattern)

All collateral/consideration transfers go through the factory's `transferFrom()` function:

```solidity
// In Redemption.sol - minting collateral
_factory.transferFrom(user, address(this), amount, collateralToken);

// In Redemption.sol - exercising with consideration
_factory.transferFrom(caller, address(this), considerationAmount, considerationToken);
```

**Benefits**:
- Single point of control for token transfers
- Easy to add Permit2 support or other approval mechanisms in the future
- Security: Only registered Redemption contracts can call this
- Gas efficient: Avoids duplicate approval checking code

---

## Frontend & Deployment (Scaffold-ETH 2)

### Frontend Architecture

Located in `core/`:
- **Framework**: Next.js 14+ with App Router (not Pages Router)
- **Web3 Stack**: RainbowKit + Wagmi + Viem
- **Styling**: Tailwind CSS v4.1.8
- **Contract Hot Reload**: Frontend auto-updates when contracts change via filesystem watchers

**Key Scaffold-ETH Hooks** (in `core/hooks/scaffold-eth/`):
- `useScaffoldReadContract`: Read contract state (auto-typed with ABIs)
- `useScaffoldWriteContract`: Write to contracts (with transaction feedback)
- `useScaffoldWatchContractEvent`: Real-time event watching
- `useScaffoldEventHistory`: Query historical events with pagination
- `useDeployedContractInfo`: Get deployed contract addresses and ABIs
- `useTargetNetwork`: Get current target network configuration

**Key Scaffold-ETH Components** (in `core/components/scaffold-eth/`):
- `<Address>`: Display Ethereum addresses with ENS support and copy functionality
- `<AddressInput>`: Input field for addresses with ENS resolution
- `<Balance>`: Display ETH/token balances with USD conversion
- `<EtherInput>`: Number input with ETH/USD conversion
- `<Contract*>`: Auto-generated UI components for contract interaction

**Contract Interactions**:
Always use Scaffold-ETH hooks (never raw wagmi/viem directly) for automatic network switching, error handling, and type safety:

```typescript
// Reading contract state
const { data: balance } = useScaffoldReadContract({
  contractName: "Option",
  functionName: "balanceOf",
  args: [address],
  watch: true, // Auto-refresh on block changes
});

// Writing to contract
const { writeContractAsync, isPending } = useScaffoldWriteContract("Option");
await writeContractAsync({
  functionName: "mint",
  args: [amount],
  value: 0n, // For payable functions
});

// Watching events
useScaffoldWatchContractEvent({
  contractName: "Redemption",
  eventName: "Redeemed",
  onLogs: (logs) => {
    console.log("Redemption events:", logs);
  },
});
```

---

### Deployment Process & Auto-Generated Contract Files

#### How Deployment Works

When you run `yarn deploy`:

1. **Foundry Deployment Script Runs** (`foundry/script/Deploy.s.sol`):
   ```solidity
   // Deploys template contracts
   Redemption redemptionTemplate = new Redemption(...);
   Option optionTemplate = new Option(...);

   // Deploys factory with templates
   OptionFactory factory = new OptionFactory(
       address(redemptionTemplate),
       address(optionTemplate),
       0.001e18  // 0.1% fee
   );

   // Optionally creates initial options
   factory.createOption(...);
   ```

2. **Deployment Info Exported** to `foundry/broadcast/`:
   - Chain-specific deployment data (addresses, ABIs, transaction hashes)
   - Format: `Deploy.s.sol/<chainId>/run-latest.json`

3. **Scaffold-ETH Auto-Generates TypeScript File**:
   - Reads deployment data from `broadcast/` directory
   - Generates `core/contracts/deployedContracts.ts`
   - Creates fully-typed contract configuration

#### The `deployedContracts.ts` File

This file is **automatically generated** and contains:

```typescript
// core/contracts/deployedContracts.ts

const deployedContracts = {
  31337: {  // Local Anvil chainId
    OptionFactory: {
      address: "0x5FbDB2315678afecb367f032d93F642f64180aa3",
      abi: [
        {
          type: "function",
          name: "createOption",
          inputs: [
            { name: "collateral", type: "address" },
            { name: "consideration", type: "address" },
            { name: "expirationDate", type: "uint40" },
            { name: "strike", type: "uint96" },
            { name: "isPut", type: "bool" }
          ],
          outputs: [{ type: "address" }],
          stateMutability: "nonpayable"
        },
        // ... all other ABI entries
      ],
      inheritedFunctions: {
        owner: "@openzeppelin/contracts/access/Ownable.sol",
        // ...
      }
    },
    Option: {
      address: "0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512",
      abi: [ /* ... */ ]
    },
    Redemption: {
      address: "0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0",
      abi: [ /* ... */ ]
    }
  },
  1301: {  // Unichain Sepolia
    // ... same structure for different network
  }
} as const;

export default deployedContracts;
```

**Key Features**:
- ✅ **Fully Type-Safe**: TypeScript knows all contract methods, events, and return types
- ✅ **Network-Specific**: Different addresses per network
- ✅ **Auto-Updates**: Regenerates on every deployment
- ✅ **Version Controlled**: Can commit to track deployment history across networks
- ✅ **ABI Included**: No need to manually copy ABIs from Foundry

#### Using Deployed Contracts in Frontend

The hooks automatically use this file:

```typescript
// The hook knows "Option" exists and has "mint" function with specific args
const { writeContractAsync } = useScaffoldWriteContract("Option");

// TypeScript will autocomplete and type-check:
await writeContractAsync({
  functionName: "mint", // ✓ Type-safe
  args: [BigInt(10)],   // ✓ Knows it needs uint256
});

// TypeScript error if you try invalid function:
await writeContractAsync({
  functionName: "invalidFunction", // ❌ TypeScript error
});
```

#### Multi-Network Support

Scaffold-ETH automatically handles network switching:

```typescript
// In scaffold.config.ts
const scaffoldConfig = {
  targetNetworks: [chains.foundry, chains.unichain],
  // ...
};

// The hooks automatically use the correct network's contracts:
const { data } = useScaffoldReadContract({
  contractName: "OptionFactory",
  functionName: "fee",
  // Automatically uses correct address for current network
});
```

When user switches networks in their wallet:
1. Frontend detects network change
2. Hooks automatically use the correct contract address from `deployedContracts.ts`
3. If network not supported, shows warning to user

#### Deployment to Different Networks

```bash
# Local (Anvil) - chainId 31337
yarn deploy

# Unichain Sepolia - chainId 1301
yarn deploy --network unichain

# Ethereum Sepolia - chainId 11155111
yarn deploy --network sepolia

# Mainnet - chainId 1 (BE CAREFUL!)
yarn deploy --network mainnet
```

Each deployment updates `deployedContracts.ts` with that network's addresses.

#### Manual Contract Deployment (Advanced)

If you need to deploy specific contracts manually:

```bash
# Deploy just the factory
forge script script/Deploy.s.sol:Deploy --broadcast --rpc-url $RPC_URL

# Create an option through the factory
cast send $FACTORY_ADDRESS \
  "createOption(address,address,uint40,uint96,bool)" \
  $COLLATERAL $CONSIDERATION $EXPIRY $STRIKE false \
  --rpc-url $RPC_URL --private-key $PRIVATE_KEY

# After manual deployment, run codegen to update deployedContracts.ts
yarn deploy:verify
```

---

### Development Workflow with Frontend

**Typical Development Flow**:

1. **Modify Contracts** (`foundry/contracts/`)
   ```bash
   # Edit Option.sol, Redemption.sol, or OptionFactory.sol
   ```

2. **Run Tests** (ensure nothing broke)
   ```bash
   yarn foundry:test
   ```

3. **Deploy Locally** (starts Anvil if not running)
   ```bash
   # Terminal 1: Start local blockchain
   yarn chain

   # Terminal 2: Deploy contracts
   yarn deploy

   # This automatically:
   # - Compiles contracts
   # - Deploys to local Anvil
   # - Generates deployedContracts.ts
   # - Updates frontend
   ```

4. **Start Frontend** (in separate terminal)
   ```bash
   # Terminal 3: Start Next.js dev server
   yarn start

   # Frontend now has access to deployed contracts at:
   # http://localhost:3000
   ```

5. **Test in Browser**
   - Navigate to `http://localhost:3000/debug`
   - See all deployed contracts
   - Interact with read/write functions
   - See events in real-time

6. **Build Custom UI**
   - Create pages in `core/app/`
   - Use Scaffold-ETH hooks for contract interaction
   - Frontend auto-reloads on file changes

7. **Deploy to Network** (when ready)
   ```bash
   # Deploy contracts to testnet
   yarn deploy --network sepolia

   # Deploy frontend to Vercel
   yarn vercel
   ```

**Hot Reload Features**:
- Change contract → Auto-recompile → Auto-redeploy locally → Frontend updates
- Change frontend code → Next.js fast refresh → Instant preview
- Change deployment script → Re-run `yarn deploy` → New addresses in frontend

---

## Market Maker Package (`market-maker/`)

The market-maker package is a consolidated TypeScript service that provides liquidity for option tokens through multiple modes: direct quote server, Bebop RFQ integration, and Bebop price relay.

### Package Structure

```
market-maker/
├── src/
│   ├── direct.ts          # Entry point for standalone quote server
│   ├── bebop.ts           # Entry point for Bebop RFQ client
│   ├── relay.ts           # Entry point for Bebop price relay
│   │
│   ├── modes/             # Mode implementations
│   │   ├── direct.ts      # HTTP + WebSocket quote server
│   │   ├── bebop.ts       # Bebop RFQ handler
│   │   └── relay.ts       # Bebop price relay
│   │
│   ├── pricing/           # Pricing core (shared across modes)
│   │   ├── blackScholes.ts    # Black-Scholes with Greeks
│   │   ├── pricer.ts          # Pricing engine
│   │   ├── spotFeed.ts        # On-chain spot price feed
│   │   └── types.ts           # Pricing types
│   │
│   ├── servers/           # Server implementations
│   │   ├── httpApi.ts         # Express HTTP quote API
│   │   ├── wsStream.ts        # WebSocket price broadcast
│   │   └── wsRelay.ts         # WebSocket relay server
│   │
│   ├── bebop/             # Bebop integration
│   │   ├── client.ts          # Bebop RFQ WebSocket client
│   │   ├── relay.ts           # Bebop pricing relay
│   │   ├── signing.ts         # Quote signing
│   │   ├── types.ts           # Bebop types
│   │   └── proto/             # Protobuf definitions
│   │
│   ├── config/            # Chain/token configuration
│   │   ├── chains.ts          # 8 chains with Chainlink feeds
│   │   ├── tokens.ts          # Token addresses per chain
│   │   ├── options.ts         # Option deployment tracking
│   │   ├── metadata.ts        # Fetch option params from chain
│   │   └── registry.ts        # Option address registry
│   │
│   ├── constants.ts
│   └── types.ts
│
├── package.json
├── tsconfig.json
└── .env.example
```

### Running Market Maker Services

```bash
cd market-maker

# Standalone quote server (HTTP + WebSocket)
yarn direct       # Production
yarn dev:direct   # Development with watch mode

# Bebop RFQ client (PMM integration)
yarn bebop        # Production
yarn dev:bebop    # Development with watch mode

# Bebop price relay (relay Bebop prices to local clients)
yarn relay        # Production
yarn dev:relay    # Development with watch mode
```

### Environment Variables

**Common** (all modes):
```bash
CHAIN_ID=8453              # Default chain (Base, Unichain, etc.)
MAKER_ADDRESS=0x...
PRIVATE_KEY=0x...          # For signing quotes
```

**Direct Mode** (standalone quote server):
```bash
HTTP_PORT=3010             # HTTP API port
WS_PORT=3011               # WebSocket stream port
DEFAULT_IV=0.8             # Implied volatility
RISK_FREE_RATE=0.05        # Risk-free rate
BID_SPREAD=0.02            # Bid spread (2%)
ASK_SPREAD=0.02            # Ask spread (2%)
SPOT_POLL_INTERVAL=30000   # Spot price update interval (ms)
PRICE_BROADCAST_INTERVAL=5000  # WebSocket broadcast interval
```

**Bebop Mode** (RFQ client):
```bash
BEBOP_MARKETMAKER=xxx      # Bebop market maker ID
BEBOP_AUTHORIZATION=xxx    # Bebop auth token
BEBOP_API_URL=https://api.bebop.xyz
CHAIN=ethereum             # Chain name for Bebop
```

**Relay Mode** (price relay):
```bash
RELAY_WS_PORT=3004         # WebSocket relay port
BEBOP_CHAINS=ethereum,base,arbitrum  # Chains to relay
```

### Key Modules

#### Pricing Core (`pricing/`)

**`blackScholes.ts`** - Black-Scholes option pricing with Greeks:
```typescript
// Core BS formula with Greeks
blackScholesPrice({ spot, strike, timeToExpiry, volatility, riskFreeRate, isPut }): {
  price: number;
  delta: number;
  gamma: number;
  theta: number;
  vega: number;
}

// Calculates bid/ask with spread
calculateBidAsk(spot, strike, expirationTimestamp, isPut, volatility, riskFreeRate, spreadPercent): { bid, ask }
```

**Critical: Put price normalization**
```typescript
// For puts: 1 option token = right to sell (1/strike) of underlying
// So put price per token = BS price / strike
if (isPut && strike > 0) {
  midPrice = midPrice / strike;
}
```

**`pricer.ts`** - Pricing engine:
- Manages option pricing across all tokens
- Handles RFQ quote generation
- Integrates with spot price feed

**`spotFeed.ts`** - On-chain spot price feed:
- Fetches prices from Chainlink price feeds
- Fallback to Uniswap V3 TWAP for chains without Chainlink
- Configurable via `config/chains.ts`

#### Chain Configuration (`config/`)

**`chains.ts`** - Multi-chain support:
```typescript
interface ChainConfig {
  id: number;
  name: string;
  rpcUrl: string;
  blockExplorer: string;
  nativeCurrency: { name: string; symbol: string; decimals: number };
  priceFeed: {
    ethUsd?: string;       // Chainlink ETH/USD
    uniV3Pool?: string;    // Uniswap V3 pool for TWAP
  };
}

// Supported chains: Ethereum, Base, Arbitrum, Unichain (+ testnets)
getChain(chainId): ChainConfig
getChainByName(name): ChainConfig
```

**`tokens.ts`** - Token addresses per chain:
```typescript
interface TokenConfig {
  address: string;
  symbol: string;
  decimals: number;
  name: string;
}

// WETH, USDC, USDT, DAI, etc. for all chains
getToken(chainId, symbol): TokenConfig
getTokenByAddress(chainId, address): TokenConfig
```

**`options.ts`** - Option deployment tracking:
```typescript
interface OptionDeployment {
  factory: string;
  options: string[];  // Deployed option contract addresses
}

getOptionFactory(chainId): string
getOptionAddresses(chainId): string[]
isOptionToken(chainId, address): boolean
```

**`metadata.ts`** - Fetch option parameters from chain:
```typescript
interface OptionMetadata {
  address: string;
  redemptionAddress: string;
  strike: number;              // Normalized to USD (inverted for puts)
  expirationTimestamp: number; // Unix timestamp
  isPut: boolean;
  collateralAddress: string;
}

fetchAllOptionMetadata()     // Fetches metadata for all options
getOptionMetadata(address)   // Returns cached metadata
```

**Critical: Strike normalization for puts**
```typescript
// Contract stores put strikes inverted (WETH per USDC instead of USDC per WETH)
if (isPut && strikeNum > 0) {
  strikeNum = 1 / strikeNum;  // Convert to same format as calls
}
```

### Strike Price Encoding (Calls vs Puts)

The protocol stores strikes differently for calls vs puts:

| Type | Collateral | Consideration | Strike Encoding | Example |
|------|------------|---------------|-----------------|---------|
| Call | WETH | USDC | USDC per WETH | 2000 (pay 2000 USDC for 1 WETH) |
| Put | USDC | WETH | WETH per USDC | 0.0005 (pay 0.0005 WETH for 1 USDC) |

**For Black-Scholes, both need to be in "USDC per WETH" format**, so puts are inverted:
- Raw put strike: `0.0005`
- Normalized: `1 / 0.0005 = 2000`

### Option Token Units

**Call tokens**: 1 token = right to buy 1 WETH at strike price
- BS price is correct as-is

**Put tokens**: 1 token = right to sell (1/strike) WETH, receiving 1 USDC
- This is 1/strike of a standard put
- Price per token = BS price / strike

Example with $2000 strike:
- Standard put on 1 WETH worth $400 → put token worth $400/2000 = $0.20

### Bebop Integration

The market-maker integrates with Bebop via **two WebSocket connections**:

#### 1. **RFQ Connection** (Request for Quote)
Receives quote requests from Bebop and responds with signed quotes.

#### 2. **Pricing Stream** (Protobuf)
Continuously sends price updates to Bebop every 10 seconds using Protobuf format.

**Files**:
- `src/bebop/client.ts` - RFQ WebSocket client
- `src/bebop/pricingStream.ts` - Protobuf pricing stream
- `src/bebop/proto/pricing_pb.js` - Protobuf encoder

**Price Filtering**:
```typescript
// Skip options with zero prices (Bebop rejects these)
if (bidPrice <= 0 || askPrice <= 0) continue;

// Skip options with spreads > 500 bps (5%)
const spreadBps = ((ask - bid) / mid) * 10000;
if (spreadBps > 500) continue;
```

### Centralized RPC Client Architecture

All blockchain RPC calls use a centralized client factory for consistency:

**Single Source of Truth**:
- `src/config/client.ts` - RPC client factory
- `src/config/chains.ts` - Chain configurations with RPC URLs

**Usage**:
```typescript
import { getPublicClient, getWalletClient } from "./config/client";

// Read blockchain data
const client = getPublicClient();
const balance = await client.getBalance({ address: "0x..." });

// Send transactions
const wallet = getWalletClient();
const hash = await wallet.sendTransaction({ ... });
```

**Environment Variables**:
```bash
# Chain selection
CHAIN_ID=1  # 1=Ethereum, 8453=Base, 42161=Arbitrum, etc.

# RPC URL override (optional)
RPC_ETHEREUM=https://eth.drpc.org
RPC_BASE=https://mainnet.base.org
```

### Metadata Caching System

Option metadata is fetched once and cached for fast startup:

**Fetch and Save** (run once per chain):
```bash
cd market-maker
yarn fetch-metadata  # Fetches from chain, saves to data/metadata-{chainId}.json
```

**Auto-Load** (fast startup):
- Services automatically load from `data/metadata-{chainId}.json` (~5ms)
- Falls back to fetching from chain if file doesn't exist (~500ms+)

**Performance**: 100x faster startup with cached metadata

---

## Trading Frontend (`core/`)

The trading UI built with Next.js for buying/selling options.

### Key Components

```
core/app/
├── trade/
│   ├── page.tsx                    # Main trading page
│   ├── components/
│   │   ├── OptionsGrid.tsx         # Options chain display (calls/puts by strike/expiry)
│   │   └── TradePanel.tsx          # Order entry panel
│   └── hooks/
│       └── useTradableOptions.ts   # Fetches options from OptionCreated events
└── hooks/
    └── usePricingStream.ts         # WebSocket connection for live prices
```

### `useTradableOptions` Hook

Fetches all deployed options by reading `OptionCreated` events from the factory:

```typescript
interface TradableOption {
  optionAddress: string;
  collateralAddress: string;
  considerationAddress: string;
  expiration: bigint;
  strike: bigint;           // Raw from contract (18 decimals)
  isPut: boolean;
  redemptionAddress: string;
}
```

### `OptionsGrid` Component

Displays options chain with:
- Strikes as rows
- Expirations as columns
- Calls on left, Puts on right
- Bid/Ask prices from pricing stream

**Strike normalization in grid** (same logic as market-maker):
```typescript
// For puts, invert the strike price to align with calls
if (option.isPut && option.strike > 0n) {
  normalizedStrike = (10n ** 36n) / option.strike;
}
```

### `usePricingStream` Hook

Connects to market-maker's pricing WebSocket:
```typescript
const { getPrice, isConnected } = usePricingStream({ enabled: true });
const price = getPrice(optionAddress);  // { bids: [[price, size]], asks: [[price, size]] }
```

---

## Important Implementation Notes

### Security Considerations
- All state-changing functions use `nonReentrant` modifier
- Checks-Effects-Interactions pattern followed consistently
- Input validation via custom modifiers: `validAmount`, `validAddress`, `sufficientBalance`
- Emergency pause mechanism via `locked` flag (prevents transfers only)

### Testing Approach
Tests in `foundry/test/Option.t.sol`:
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

1. **Modify contracts** in `foundry/contracts/`
2. **Update deployment scripts** in `foundry/script/` if needed
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
