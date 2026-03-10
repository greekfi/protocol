# Design Analysis - Greek Protocol

A deep understanding of the protocol's architecture, token flows, and design rationale. Separated into two systems: the **Core Option System** and the **OpHook Trading System**.

---

# Part 1: Core Option System (Option, Redemption, Factory)

## 1. Design Philosophy

### The Problem

Traditional DeFi options protocols have a fundamental limitation: the short side is illiquid. In Opyn, the short position is a vault ID managed by a Controller -- not transferable. In Hegic, positions are ERC721 NFTs -- not fungible. In Dopex, positions are locked into epoch-based vaults.

### The Solution: Dual-Token ERC20 Positions

This protocol makes **every position a standard ERC20 token**:

- **Option** (long): the right to exercise -- buy collateral at the strike price
- **Redemption** (short): the obligation side -- a claim on escrowed collateral + any consideration received from exercises

Because both sides are ERC20s, they can be traded on AMMs, used as lending collateral, or composed into arbitrary DeFi strategies. A market maker can write covered calls, sell the Option tokens, and retain the Redemption tokens. Or sell the Redemption tokens too, transferring the obligation.

### Key Design Tradeoffs

| Decision | Tradeoff |
|----------|----------|
| **Full collateralization, no oracle** | Capital-inefficient vs margin systems, but no liquidations and dramatically simpler |
| **EIP-1167 clones per option series** | More bytecode deployed, but each option is a real ERC20 address that works with wallets, DEXes, block explorers |
| **Centralized transferFrom via Factory** | Extra approval step, but single choke point for access control |
| **Auto-settle on transfer** | Breaks ERC20 principle of least surprise, but eliminates dead offsetting positions |
| **Auto-mint on transfer** | Non-standard, but enables one-step "write-and-sell" for market makers |

---

## 2. Token Lifecycle (Concrete Numbers)

**Setup:** WETH (18 dec) collateral, USDC (6 dec) consideration, strike = 2000e18, fee = 0.5% (5e15), amount = 1e18 (1 WETH)

### Mint

Alice calls `option.mint(1e18)`:

```
Option.mint(alice, 1e18)
  └─> mint_(alice, 1e18)
       ├─> redemption.mint(alice, 1e18)
       │    ├─> factory.transferFrom(alice, redemption, 1e18, WETH)
       │    │    └─> WETH.safeTransferFrom(alice, redemption, 1e18)
       │    ├─> fee-on-transfer check (balance before/after)
       │    ├─> fee_ = (1e18 * 5e15) / 1e18 = 5e15 (0.005 WETH)
       │    ├─> fees += 5e15
       │    └─> _mint(alice, 1e18 - 5e15) = 0.995e18 Redemption tokens
       │
       ├─> amountMinusFees = 1e18 - 5e15 = 0.995e18
       └─> _mint(alice, 0.995e18) Option tokens
```

**Result:**

| | Alice | Redemption Contract |
|---|---|---|
| WETH | -1.0 | +1.0 (of which 0.005 is fees) |
| Option tokens | +0.995 | -- |
| Redemption tokens | +0.995 | -- |

Note: Alice must have called both `WETH.approve(factory, ...)` AND `factory.approve(WETH, ...)` beforehand.

### Exercise

Alice exercises 0.5e18 Option tokens:

```
Option.exercise(alice, 0.5e18)
  ├─> _burn(alice, 0.5e18) Option tokens
  └─> redemption.exercise(alice, 0.5e18, alice)
       ├─> consAmount = toConsideration(0.5e18)
       │    = mulDiv(0.5e18, 2000e18 * 1e6, 1e18 * 1e18)
       │    = mulDiv(5e17, 2e24, 1e36)
       │    = 1e42 / 1e36
       │    = 1,000,000 (= 1000 USDC)
       ├─> factory.transferFrom(alice, redemption, 1000000, USDC)
       └─> collateral.safeTransfer(alice, 0.5e18 WETH)
```

**Result:**

| | Alice | Redemption Contract |
|---|---|---|
| WETH | +0.5 (received) | 0.5 remaining (0.005 is fees) |
| USDC | -1000 (paid) | +1000 (received) |
| Option | 0.495 remaining | -- |
| Redemption | 0.995 (unchanged) | -- |

### Redeem (Pre-Expiry, Paired)

Alice redeems 0.495e18 (requires burning equal Option + Redemption):

```
Option.redeem(0.495e18)
  └─> redeem_(alice, 0.495e18)
       ├─> _burn(alice, 0.495e18) Option tokens
       └─> redemption._redeemPair(alice, 0.495e18)
            └─> _redeem(alice, 0.495e18)
                 ├─> balance = WETH.balanceOf(redemption) - fees
                 │           = 0.5e18 - 5e15 = 0.495e18
                 ├─> collateralToSend = min(0.495e18, 0.495e18) = 0.495e18
                 ├─> _burn(alice, 0.495e18) Redemption tokens
                 └─> collateral.safeTransfer(alice, 0.495e18 WETH)
```

**Result:** Alice gets 0.495 WETH back. She still holds 0.5e18 Redemption tokens (her short position on the exercised portion).

### Redeem (Post-Expiry)

After expiration, Alice redeems her remaining 0.5e18 Redemption tokens.

**Scenario A -- All exercised (no collateral left):**
```
balance = WETH.balanceOf(redemption) - fees = 5e15 - 5e15 = 0
collateralToSend = 0
→ _redeemConsideration(alice, 0.5e18)
  → toConsideration(0.5e18) = 1,000,000 USDC
  → _burn(alice, 0.5e18 Redemption)
  → consideration.safeTransfer(alice, 1,000,000 USDC)
```
Alice receives 1000 USDC (the consideration paid by exercisers).

**Scenario B -- None exercised (all collateral remains):**
```
balance = 1e18 - 5e15 = 0.995e18
collateralToSend = 0.995e18
→ _burn(alice, 0.995e18 Redemption)
→ collateral.safeTransfer(alice, 0.995e18 WETH)
```
Alice gets 0.995 WETH back (full collateral minus fees).

**Scenario C -- Partially exercised:**
```
balance = 0.5e18 - 5e15 = 0.495e18
collateralToSend = 0.495e18 (all remaining WETH)
→ _burn(alice, 0.495e18 Redemption)
→ _redeemConsideration(alice, 0.5e18 - 0.495e18 = 0.005e18)
  → toConsideration(0.005e18) = 10,000 USDC (= 10 USDC)
→ collateral.safeTransfer(alice, 0.495e18 WETH)
```
Alice receives 0.495 WETH + 10 USDC.

### Auto-Settle on Transfer

Bob holds 0.3e18 Redemption tokens. Alice transfers 0.2e18 Option tokens to Bob:

```
Option.transfer(bob, 0.2e18)
  ├─> balance = balanceOf(alice) >= 0.2e18? Yes → no auto-mint
  ├─> super.transfer(bob, 0.2e18)  // standard ERC20 transfer
  └─> redemption.balanceOf(bob) = 0.3e18 > 0
       └─> redeem_(bob, min(0.3e18, 0.2e18) = 0.2e18)
            ├─> _burn(bob, 0.2e18) Option tokens
            └─> redemption._redeemPair(bob, 0.2e18)
                 └─> burns 0.2e18 Redemption, sends 0.2e18 WETH to Bob
```

**Result:** Bob received Option tokens, but they were immediately netted against his Redemption tokens. He ends up with:
- 0 Option tokens (auto-redeemed)
- 0.1e18 Redemption tokens (0.3 - 0.2)
- +0.2e18 WETH (collateral returned)

---

## 3. Ownership & Trust Model

```
OptionFactory (UUPS Proxy)
│ owner: protocol deployer
│ can: upgrade, blocklist tokens, adjust global fee, claim fees
│
├── creates via Clones.clone() ──►
│
│  Option (EIP-1167 clone)
│  │ owner: whoever called createOption()
│  │ can: lock/unlock, adjustFee, claimFees
│  │ anyone can: mint, exercise, redeem, transfer
│  │
│  └── owns ──►
│
│     Redemption (EIP-1167 clone)
│       owner: the Option contract (NOT a user)
│       only Option can call: mint, exercise, _redeemPair,
│                              lock, unlock, adjustFee, claimFees
│       anyone can call: redeem (post-expiry), sweep, redeemConsideration
│       holds: ALL collateral + ALL consideration + fee accounting
```

### Why Centralized transferFrom?

All token movements route through `Factory.transferFrom()`:

```
User ──approve──► Factory ──safeTransferFrom──► Redemption
         │
         └── factory.approve() (internal allowance)
```

Benefits:
- **Access control:** Only registered Redemption contracts can trigger transfers
- **Single approval point:** One `type(uint256).max` approval works across all options for that token
- **Extensibility:** Factory can be upgraded (UUPS) to support Permit2 or other mechanisms

### Why Dual Approval?

Users must grant two approvals:
1. `WETH.approve(factory, amount)` -- ERC20 tells the token "Factory can move my tokens"
2. `factory.approve(WETH, amount)` -- Factory's internal accounting "I authorize this much"

This separation means the Factory enforces its own rate-limiting independently of the token's approval system.

---

## 4. State Machine

```
                  lock()                    time passes
   ACTIVE  ──────────────►  LOCKED  ──────────────────►  LOCKED+EXPIRED
     │                        │                                │
     │       unlock()         │                                │
     │  ◄─────────────────────│                                │
     │                                                         │
     │       time passes                                       │
     ├──────────────────────►  EXPIRED                         │
                                │           unlock()           │
                                │  ◄───────────────────────────│
```

| State | Allowed | Blocked |
|-------|---------|---------|
| **ACTIVE** | mint, exercise, redeem (paired), redeemConsideration, transfer, lock/unlock, adjustFee | -- |
| **LOCKED** | unlock (owner only), view functions | Everything else |
| **EXPIRED** | redeem (post-expiry), sweep, redeemConsideration, transfer (if recipient has no Redemption tokens) | mint, exercise, paired redeem |
| **LOCKED+EXPIRED** | unlock (owner only) | Everything else |

---

## 5. Fee Architecture

Fees are collected **at mint time only**, denominated in the **collateral token**.

```
User deposits 1.0 WETH
  │
  ▼
Redemption contract receives 1.0 WETH
  ├── 0.005 WETH → fees accumulator (segregated)
  ├── 0.995 Redemption tokens minted
  └── 0.995 Option tokens minted

Fee claim flow:
  factory.claimFees(options[], tokens[])
    └── option.claimFees()
         └── redemption.claimFees()
              └── collateral.safeTransfer(factory, fees)
                   └── factory sends to owner()
```

Key: `_redeem()` calculates available collateral as `balanceOf(this) - fees`, ensuring fees are never distributed to redeemers.

---

## 6. Auto-Settle Mechanism

### Why It Exists

When a market maker writes covered calls, they mint Option + Redemption, then sell the Options. If a buyer later sells them back, the market maker holds both tokens -- a fully hedged position equivalent to just holding collateral. Without auto-settle, they'd need to manually call `redeem()`. Auto-settle nets out offsetting positions automatically on receipt.

### How It Differs in transfer() vs transferFrom()

| | `transfer()` | `transferFrom()` |
|---|---|---|
| Auto-mint (if insufficient balance) | Yes | No |
| Auto-redeem (if recipient holds Redemption) | Yes | Yes |
| Allowance check | N/A (sender = msg.sender) | ERC20 allowance OR factory universal operator |

### Composability Implications

**Positive:** AMM LPs and traders get automatic position netting.

**Concerning:**
- Post-expiry, auto-settle calls `redeem_()` which has `notExpired` → transfers revert if recipient holds Redemption tokens
- A contract receiving Option tokens may unexpectedly have its Redemption balance reduced
- `transfer()` auto-mint can pull collateral via the Factory -- no standard ERC20 consumer expects this

---

## 7. Put vs Call Design

Puts and calls share **100% of the execution code**. The difference is purely in role assignment:

| | Call (WETH/USDC, strike 2000) | Put (WETH/USDC, strike 2000) |
|---|---|---|
| collateral | WETH | USDC |
| consideration | USDC | WETH |
| strike | 2000e18 | 0.0005e18 (= 1/2000) |
| isPut | false | true |
| Mint deposits | 1 WETH | 2000 USDC |
| Exercise pays | 2000 USDC → gets 1 WETH | 1 WETH → gets 2000 USDC |

The `isPut` flag is used ONLY in `name()` for display: `displayStrike = isPut ? (1e36 / strike) : strike` so both show "2000" to users.

---

## 8. Decimal Normalization

### toConsideration(amount)

```
mulDiv(amount, strike * 10^consDecimals, 10^18 * 10^collDecimals)
```

**Call example** (1 WETH → USDC at strike 2000):
```
mulDiv(1e18, 2000e18 * 1e6, 1e18 * 1e18)
= mulDiv(1e18, 2e24, 1e36)
= 2e42 / 1e36
= 2,000,000,000 (= 2000 USDC in 6-dec)
```

**Put example** (2000 USDC → WETH at strike 0.0005e18):
```
mulDiv(2000e6, 5e14 * 1e18, 1e18 * 1e6)
= mulDiv(2e9, 5e32, 1e24)
= 1e42 / 1e24
= 1e18 (= 1 WETH)
```

**Same-decimal example** (1 WETH → DAI at strike 2000, both 18 dec):
```
mulDiv(1e18, 2000e18 * 1e18, 1e18 * 1e18)
= 2e57 / 1e36
= 2000e18 (= 2000 DAI)
```

### Why 18 Decimals for Strike?

- **Uniformity:** Same encoding regardless of token decimals
- **Precision:** Smallest representable strike is 10^-18, more than sufficient
- **Overflow safety:** `Math.mulDiv` uses 512-bit intermediates, so even large `amount * strike * 10^consDecimals` values are handled correctly
- **Range:** uint96 input limits strike to ~79 billion, adequate for any financial instrument

---

---

# Part 2: OpHook Trading System (Hook, Pricing, Vault, BatchMinter)

## 1. OpHook Architecture

### What It Does

OpHook is a Uniswap v4 hook that creates an **on-chain options market** with Black-Scholes pricing. It is NOT a traditional AMM -- it completely overrides Uniswap v4's swap math using the `beforeSwapReturnDelta` mechanism. The v4 pool exists purely as a routing/discovery layer; actual pricing comes from `OptionPrice.sol`.

This is a "virtual AMM" or "custom curve hook" pattern: the Uniswap v4 pool is a shell that delegates all swap execution to the hook.

### Hook Permissions

| Hook | Enabled? | Purpose |
|------|----------|---------|
| `beforeSwap` | Yes | Core logic -- intercepts swaps, computes BS price, mints/transfers options |
| `beforeSwapReturnDelta` | Yes | Tells PoolManager to use hook's deltas instead of AMM curve |
| `beforeAddLiquidity` | Yes | To **REVERT** -- no traditional AMM liquidity allowed |
| `beforeDonate` | Yes | To **REVERT** -- donations not supported |
| All others | No | Not needed |

### Relationship to PoolManager

```
PoolManager (singleton, holds all token balances)
     │
     ├── pool(optionToken/cashToken, hook=OpHook)
     │     └── no AMM liquidity, just a routing entry
     │
     └── OpHook (the hook contract)
           ├── holds WETH (collateral for minting)
           ├── holds USDC (reserves for buybacks)
           ├── holds option token inventory
           └── calls PoolManager.take/sync/settle for accounting
```

---

## 2. Swap Flows

### Buying Options (Cash → Option)

User spends 1000 USDC to buy call options. Option price is ~100 USDC per option.

```
_beforeSwap(amountSpecified = -1000e6)  // negative = exact input
  │
  ├── pool = optionPools[poolId]
  ├── cashForOption = true
  │
  ├── calculateOption(pool, amountSpecified):
  │    ├── collateralPrice = getCollateralPrice(WETH) → reads v3 slot0()
  │    ├── price = getPrice(collateralPrice, option) → Black-Scholes → ~100e18
  │    ├── optionAmount = mulDiv(cashAmount, 1e18, price)
  │    └── return { cashAmount, optionAmount }
  │
  ├── poolManager.take(USDC, hook, cashAmount)     // hook receives USDC from PM
  ├── poolManager.sync(optionToken)                 // snapshot option balance
  ├── option.mint(optionAmount)                     // mint new options (uses hook's WETH)
  ├── optionToken.safeTransfer(PM, actualMinted)    // send options to PM
  ├── poolManager.settle()                          // PM credits the options
  │
  └── return BeforeSwapDelta(+cashAmount, -actualMinted)
```

After `_beforeSwap` returns, the swap caller:
- **Settles** USDC (pays into PoolManager)
- **Takes** option tokens (claims from PoolManager)

### Selling Options (Option → Cash)

User sells 1e18 option tokens back to the hook:

```
_beforeSwap(amountSpecified = -1e18)  // selling options
  │
  ├── cashForOption = false
  │
  ├── calculateCash(pool, amountSpecified):
  │    ├── price = getPrice(...) → ~100e18
  │    ├── cashAmount = mulDiv(optionAmount, price, 1e18)
  │    └── return { cashAmount, optionAmount }
  │
  ├── poolManager.take(optionToken, hook, optionAmount)  // hook receives options
  ├── poolManager.sync(USDC)                              // snapshot USDC balance
  ├── USDC.safeTransfer(PM, cashAmount)                   // hook pays USDC from reserves
  ├── poolManager.settle()                                // PM credits USDC
  │
  └── return BeforeSwapDelta(+optionAmount, -cashAmount)
```

**Key:** In the sell direction, the hook pays from its own USDC reserves. It does NOT exercise or burn the received options -- it holds them as inventory.

### Direct `swapForOption()` Path

Bypasses the Uniswap v4 PoolManager entirely:

```
swapForOption(optionToken, cashToken, amount, to)
  ├── calculateCash() → determine USDC cost
  ├── transferCash() → pull USDC from user via safeTransferFrom
  ├── option.mint(optionAmount) → mint using hook's WETH
  └── option.transfer(to, optionAmount) → send to user
```

| | v4 Pool Path | Direct swapForOption() |
|---|---|---|
| Routing | Via UniversalRouter / PoolManager | Direct contract call |
| Composability | Composable with other v4 swaps | Standalone |
| Direction | Buy and sell | Buy only |
| Gas | Higher (PoolManager overhead) | Lower |
| Discovery | DEX aggregators can find it | Must know the contract |

---

## 3. Pricing Architecture

### Black-Scholes Implementation (OptionPrice.sol)

Fully on-chain BS using fixed-point (1e18 scale) with lookup tables:

```
blackScholesPrice(S, K, T, sigma, r, isPut):

  t = T / 31536000                    // seconds → years
  sqrtT = sqrt(t)
  sigmaSqrtT = sigma * sqrtT
  lnks = ln(S/K)                      // log moneyness
  mu = (r + sigma^2/2) * t
  d1 = (lnks + mu) / sigmaSqrtT
  d2 = d1 - sigmaSqrtT

  Call: C = S * N(d1) - K * e^(-rT) * N(d2)
  Put:  P = K * e^(-rT) * N(-d2) - S * N(-d1)
```

**Math building blocks:**

| Function | Implementation | Precision |
|----------|---------------|-----------|
| `log2(x)` | CLZ opcode (Solidity 0.8.33) + 64-bit fractional refinement | ~19 decimal digits |
| `ln(x)` | `log2(x) * ln(2)`, handles x < 1 via `ln(x) = -ln(1/x)` | ~18 decimal digits |
| `expNeg(x)` | 100-entry lookup table (0.05 steps), linear interpolation | ~0.1% error near boundaries |
| `normCdf(x)` | 101-entry lookup table (0.05 steps), linear interpolation, symmetry for negative x | Covers \|x\| < 5.0 |
| `mul18/div18` | `(a * b) / 1e18` and `(a * 1e18) / b` | Standard fixed-point |

**Concrete example** (ATM call, S=K=3600, T=30 days, sigma=20%, r=5%):
```
t = 0.08219 years
sqrtT = 0.2867
sigmaSqrtT = 0.05734
d1 = 0.10033
d2 = 0.04299
N(d1) = 0.5399, N(d2) = 0.5172
e^(-rT) = 0.9959
C = 3600 * 0.5399 - 3600 * 0.9959 * 0.5172 = ~$92.30
```

### Price Oracle (getCollateralPrice)

Reads from a **Uniswap v3 pool** (not v4) using `slot0().sqrtPriceX96`:

```
getCollateralPrice(WETH):
  ├── pool = collateralPricePool[WETH]  // e.g., WETH/USDC 0.05% v3 pool
  ├── sqrtPriceX96 = pool.slot0()       // instantaneous spot price
  ├── priceX64 = getPriceX64(sqrtPriceX96)  // square and shift
  ├── price = (priceX64 * 1e18) >> 64   // convert to 1e18 fixed-point
  └── adjust for token ordering and decimals
```

Note: This reads spot price, not TWAP. Susceptible to same-block manipulation via flash loans.

### How calculateCash/calculateOption Work

Simple proportional conversions at 1e18 scale:

```
// Options received for cash:
calculateOption(cashAmount, price) = mulDiv(cashAmount, 1e18, price)

// Cash needed for options:
calculateCash(optionAmount, price) = mulDiv(optionAmount, price, 1e18)
```

### Global Parameters

| Parameter | Default | Set By |
|-----------|---------|--------|
| `volatility` | 20% (0.2e18) | `setVolatility()` -- owner only |
| `riskFreeRate` | 5% (0.05e18) | `setRiskFreeRate()` -- owner only |

These are global across all options priced by this OptionPrice instance. No per-strike volatility surface exists.

---

## 4. Pool Initialization & Management

### What initPool() Sets Up

```
initPool(optionToken, cashToken, collateral, pricePool, fee):
  ├── Determine token ordering (currency0 < currency1)
  ├── Create PoolKey:
  │    ├── currency0/currency1 (sorted)
  │    ├── fee tier
  │    ├── tickSpacing = type(int16).max  // single tick range (AMM unused)
  │    └── hooks = address(this)
  ├── poolManager.initialize(poolKey, 1<<96)  // 1:1 price (irrelevant)
  ├── Store metadata:
  │    ├── allPools[] ← push
  │    ├── optionPools[poolId] ← OptionPool struct
  │    ├── collateralPools[collateral] ← push
  │    ├── optionPoolList[option] ← push
  │    └── collateralPricePool[collateral] ← v3 oracle pool
  └── Approve collateral to factory (max amounts)
```

### Data Model

```
allPools[]                     // flat list, used by getPrices()
optionPools[poolId]            // keyed by keccak256(PoolKey), used by _beforeSwap
collateralPools[collateral]    // grouped by collateral asset
optionPoolList[optionToken]    // grouped by option token
collateralPricePool[collateral]// v3 oracle, one per collateral
```

### OptionPool Struct

```solidity
struct OptionPool {
    address collateral;      // e.g., WETH
    address pricePool;       // Uniswap v3 pool for price oracle
    bool    collateralIsOne; // is collateral token1 in the v3 pool?
    address optionToken;     // the Option ERC20
    address cashToken;       // e.g., USDC
    bool    optionIsOne;     // is option token currency1 in the v4 pool?
    uint24  fee;             // pool fee tier
    int24   tickSpacing;     // always max (AMM unused)
    uint160 sqrtPriceX96;    // initial price (always 1:1)
    uint256 expiration;      // option expiration
    uint256 strike;          // option strike price
}
```

---

## 5. OptionPoolVault

### Intended Purpose

An ERC4626 vault where LPs deposit assets (WETH or USDC), receive shares, and earn yield from option premiums.

### Current State: Placeholder

All overridden functions delegate to the parent `ERC4626` with no custom logic. Internal hooks (`_afterDeposit`, `_afterMint`, `_afterWithdraw`, `_afterRedeem`) are empty stubs. Constructor has commented-out parameters for `_feeRecipient`, `_feeRate`, `_optionPool`. No connection to OpHook exists.

### Intended Flow (Inferred)

```
LP deposits USDC → Vault
  → Vault transfers to OpHook (mechanism TBD)
    → OpHook uses as reserves for buybacks
      → Premiums from option sales accrue
        → Flow back to Vault → increase share price
          → LP withdraws at profit
```

Similar to Ribbon Finance / Thetanuts DOV model.

---

## 6. BatchMinter

### Purpose

Reduces N separate mint transactions to one for market makers providing liquidity across multiple strike/expiry combinations.

### Flow

```
batchMint(options[], amounts[]):
  for each (option, amount):
    IOption(option).mint(msg.sender, amount)
```

Collateral is pulled from `msg.sender` (the user), not from BatchMinter. User must have:
1. ERC20 approved collateral to the Factory
2. Called `factory.approve(collateral, totalAmount)`

`previewBatchMint(amounts[])` sums the array to show total collateral needed.

---

## 7. The Bigger Picture

### Architecture

```
                                USER
                               /    \
                 [Direct path]       [Uniswap v4 path]
                      |                     |
                swapForOption()        UniversalRouter
                      |                     |
                      |              PoolManager.swap()
                      |                     |
                      ▼                     ▼
                 +---------+          +-----------+
                 | OpHook  |◄─────────| _beforeSwap()
                 |         |          +-----------+
                 | holds:  |
                 |  WETH   |     OptionPrice.sol
                 |  USDC   |     (Black-Scholes)
                 |  options |          ▲
                 +----+----+          |
                      |          getPrice()
                 Option.mint()        |
                      |          Uniswap v3 Pool
                      ▼          (price oracle)
               +-----------+     +-------------+
               | Option.sol|◄───►|Redemption.sol|
               +-----------+     +------+------+
                                        |
                                  OptionFactory
                               (clone deployer,
                                transfer router)

  [Not yet connected]
  +-----------------+       +-------------+
  |OptionPoolVault  |       | BatchMinter |
  | (LP deposits)   |       | (multi-mint)|
  +-----------------+       +-------------+
```

### Completeness Assessment

| Component | Status | Notes |
|-----------|--------|-------|
| Option.sol | Complete | Full lifecycle, well-tested (91 tests) |
| Redemption.sol | Complete | All redemption paths, fee tracking, sweep |
| OptionFactory.sol | Complete | Clones, blocklist, UUPS, fees |
| OptionPrice.sol | Complete | Full BS implementation, lookup tables |
| OpHook swap (buy) | Functional | Cash→option path works, mints new options |
| OpHook swap (sell) | Functional | Pays from reserves, no inventory management |
| OpHook.initPool() | Functional | Missing access control |
| OpHook price oracle | Functional | Uses spot (slot0) not TWAP |
| BatchMinter | Complete | Simple, does its job |
| OptionPoolVault | Placeholder | Empty hooks, no integration |
| LP capital management | Missing | No deposit/withdraw mechanism for hook reserves |
| Inventory management | Missing | Hook accumulates options on buyback, never burns/exercises |
| Hook fee/spread | Missing | Events defined but no logic |

### User Journey: Buying a Call Option

1. Option creator calls `factory.createOption(WETH, USDC, expiry, 2000e18, false)` → deploys Option + Redemption clones
2. Hook owner calls `opHook.initPool(optionAddr, USDC, WETH, v3Pool, 3000)` → creates v4 pool
3. Hook is funded with WETH (manual deposit or future vault integration)
4. User approves USDC → calls swap through v4 pool or `swapForOption()`
5. Hook reads WETH price from v3, computes BS price, mints options using its WETH
6. User receives Option ERC20 tokens
7. Before expiry: user can exercise (pay USDC, get WETH) or sell back through v4 pool
8. At expiry: options expire worthless or are exercised

---

*Generated by Claude Code -- design analysis across core option system and OpHook trading system.*
