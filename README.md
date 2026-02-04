# GreekFi Options Protocol

A dual-token options protocol where both long (Option) and short (Redemption) positions are fully transferable ERC20 tokens. Create options between any ERC20 token pairs with gas-efficient deployment using minimal proxy clones.

<h4 align="center">
  <a href="./SECURITY_AUDIT.md">🔒 Security Audit</a>
</h4>

## Core Mechanics

**Option Lifecycle:**
1. **Mint**: Deposit collateral → receive Option + Redemption tokens (1:1 minus fees)
2. **Exercise**: Burn Option + pay consideration → receive collateral (before expiration)
3. **Redeem Pair**: Burn Option + Redemption → receive collateral back (before expiration)
4. **Redeem Post-Expiration**: Burn Redemption → receive remaining collateral or equivalent consideration

**Key Features:**
- Both option sides are tradable ERC20 tokens
- Works with any ERC20 pair (WETH/USDC, WBTC/DAI, etc.)
- Strike prices encoded with 18 decimals for precision across token pairs
- Auto-settling transfers: sending Options to a Redemption holder auto-redeems matching pairs
- Gas-efficient deployment: ~95% savings via EIP-1167 minimal proxy clones

## Core Contracts

```
foundry/contracts/
├── OptionFactory.sol      # Factory contract, creates option pairs via clones
├── Option.sol             # Long position (call/right side)
├── Redemption.sol         # Short position (put/obligation side)
└── interfaces/
    ├── IOptionFactory.sol
    ├── IOption.sol
    └── IRedemption.sol
```

**Contract Responsibilities:**
- **OptionFactory**: Deploys option pairs, manages token blocklist, handles protocol fees
- **Option**: Coordinates lifecycle (mint/exercise/redeem), owns paired Redemption contract
- **Redemption**: Holds collateral, receives consideration, manages decimal normalization

## Quick Start

**Prerequisites:**
- [Node.js v22+](https://nodejs.org)
- [Yarn v2+](https://yarnpkg.com)
- [Foundry](https://foundry.sh)

**Setup:**
```bash
# Install dependencies
yarn install

# Terminal 1: Start local blockchain
yarn chain

# Terminal 2: Deploy contracts
yarn deploy

# Terminal 3: Start frontend
yarn start
```

Visit `http://localhost:3000`

## Development

**Smart Contracts:**
```bash
forge build              # Compile contracts
forge test               # Run tests
forge test -vvv          # Run with detailed output
```

**Frontend:**
- Built with Next.js, RainbowKit, Wagmi, Viem
- Auto-updates when contracts change
- Debug UI at `http://localhost:3000/debug`

**Key Directories:**
- Contracts: `foundry/contracts/`
- Tests: `foundry/test/`
- Deployment: `foundry/script/`
- Frontend: `opswap/`

## Security Notice

This protocol is under active development. See [SECURITY_AUDIT.md](./SECURITY_AUDIT.md) for complete findings.

## Documentation

For detailed architecture and implementation guide, see [CLAUDE.md](./CLAUDE.md)
