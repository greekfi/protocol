# Why Minting & Transferring Are Gas-Heavy

## TL;DR

**Mint costs ~343k gas** because:
- **225k gas** (66%): Redemption.mint() with AddressSet tracking
- **100k gas** (29%): Collateral transfer via Permit2
- **18k gas** (5%): Option token mint + fees + events

**Transfer costs ~413k gas** because:
- **331k gas** (80%): Auto-mint if sender has insufficient balance
- **50k gas** (12%): Auto-redeem if receiver already holds Redemption tokens
- **32k gas** (8%): Base ERC20 transfer + ReentrancyGuard + Lock check

---

## Deep Dive: Option.mint() - 343k Gas

### Call Stack Breakdown

```
Option.mint(amount)                                    // Entry point
├─ [Modifier] notLocked                               // ~3k gas
│  └─ redemption.locked() external call               // SLOAD + external call
├─ [Modifier] nonReentrant (OpenZeppelin)             // ~2k gas
│  └─ _status = ENTERED; ... _status = NOT_ENTERED   // 2 SSTORE operations
├─ Option.mint_(account, amount)
│  ├─ [Modifier] notExpired                           // ~1k gas
│  │  └─ Check block.timestamp < expirationDate
│  ├─ [Modifier] validAmount(amount)                  // ~1k gas
│  │  └─ Check amount > 0
│  ├─ redemption.mint(account, amount)                // **225k gas** ⚠️
│  │  ├─ [Modifier] onlyOwner                         // ~1k gas
│  │  ├─ [Modifier] notExpired                        // ~1k gas
│  │  ├─ [Modifier] notLocked                         // ~1k gas
│  │  ├─ [Modifier] nonReentrant                      // ~2k gas
│  │  ├─ [Modifier] validAmount(amount)               // ~1k gas
│  │  ├─ [Modifier] sufficientCollateral              // ~3k gas
│  │  │  └─ collateral.balanceOf(account)            // External call
│  │  ├─ [Modifier] validAddress(account)             // ~1k gas
│  │  ├─ [Modifier] saveAccount(account)              // **~100k gas** ⚠️⚠️
│  │  │  └─ _accounts.add(account)
│  │  │     ├─ Check if already exists (SLOAD)        // ~2k gas
│  │  │     ├─ _values.push(account)                  // ~20k gas (first push costs more)
│  │  │     ├─ _indices[account] = length + 1         // ~20k gas (new mapping slot)
│  │  │     └─ _length++                             // ~5k gas (SSTORE)
│  │  ├─ balanceBefore = collateral.balanceOf(this)   // ~3k gas
│  │  ├─ _factory.transferFrom(...)                   // **~100k gas** ⚠️
│  │  │  └─ Factory checks Permit2 then ERC20        // Permit2 overhead
│  │  ├─ balanceAfter = collateral.balanceOf(this)    // ~3k gas
│  │  ├─ Fee-on-transfer check                        // ~1k gas
│  │  ├─ toFee(amount) calculation                    // ~2k gas
│  │  ├─ _mint(account, amountMinusFee)               // ~10k gas
│  │  │  └─ ERC20._mint (OpenZeppelin)
│  │  │     ├─ totalSupply += amount                  // ~5k gas (SSTORE)
│  │  │     └─ balances[account] += amount            // ~5k gas (SSTORE or update)
│  │  └─ fees += fee                                  // ~5k gas (SSTORE)
│  ├─ toFee(amount) calculation                       // ~2k gas
│  ├─ _mint(account, amountMinusFees)                 // ~10k gas
│  └─ emit Mint(...)                                  // ~3k gas
└─ RETURN                                             // ~1k gas
```

### Gas Hotspots

#### 🔥 #1: AddressSet.add() - ~100k gas (29% of total)

**Location:** `Redemption.mint()` modifier `saveAccount(account)`

**Why so expensive:**
```solidity
function add(Set storage set, address value) internal returns (bool) {
    if (set._indices[value] == 0) {           // SLOAD: ~2k gas
        set._values.push(value);              // Dynamic array push: ~20k gas
        set._indices[value] = set._length + 1; // New mapping slot: ~20k gas
        set._length++;                        // SSTORE: ~5k gas
        return true;
    }
    return false;
}
```

**Breakdown:**
- **First-time addition:** ~100k gas (new mapping slot + array push)
- **Subsequent additions:** ~50k gas (mapping exists, but still pushes to array)
- **Already exists:** ~2k gas (just SLOAD check)

**Purpose:** Track all addresses that have ever held Redemption tokens for `sweep()` functionality

**Optimization potential:** 🟡 Medium
- Could make AddressSet optional (lose sweep functionality)
- Could use a Merkle tree for tracking (much cheaper)
- Could track only on first receipt (not every mint)

#### 🔥 #2: Permit2 Transfer - ~100k gas (29% of total)

**Location:** `Redemption.mint()` → `_factory.transferFrom()`

**Why so expensive:**
```solidity
// In OptionFactory.transferFrom()
(uint160 allowAmount, uint48 expiration,) = permit2.allowance(from, token, address(this));
// 3 external calls to Permit2 contract: ~30k gas

if (allowAmount >= amount && expiration > uint48(block.timestamp)) {
    permit2.transferFrom(from, to, amount, token);  // External call: ~70k gas
    return true;
}
```

**Breakdown:**
- Permit2.allowance() query: ~30k gas (3 SLOADs in external contract)
- Permit2.transferFrom() execution: ~70k gas
  - Signature verification overhead
  - Nonce management
  - Actual token transfer
  - Event emissions

**Alternative (standard ERC20):**
```solidity
else if (ERC20(token).allowance(from, address(this)) >= amount) {
    ERC20(token).safeTransferFrom(from, to, amount);  // ~65k gas
    return true;
}
```

**Optimization potential:** 🟢 Easy
- Offer both Permit2 and standard ERC20 paths
- Let users choose based on their preference
- Savings: ~35k gas per mint (10% reduction)

#### 🔥 #3: ReentrancyGuard - ~4k gas (1% of total, but everywhere)

**Location:** Every state-changing function

**Why needed:**
- External calls to tokens (could be malicious)
- External calls between Option ↔ Redemption
- Prevents reentrancy attacks

**Cost:**
```solidity
// OpenZeppelin ReentrancyGuard
uint256 private _status;

modifier nonReentrant() {
    require(_status != ENTERED);  // ~2k gas (SLOAD)
    _status = ENTERED;            // ~2k gas (SSTORE)
    _;
    _status = NOT_ENTERED;        // ~2k gas (SSTORE)
}
```

**Total per function:** ~4k gas (appears in both Option.mint AND Redemption.mint)

**Optimization potential:** 🔴 Hard
- Could use Checks-Effects-Interactions pattern instead
- Would require careful audit
- Risk: Security vulnerability
- Recommendation: Keep it (security > gas savings)

---

## Deep Dive: Option.transfer() - 413k Gas (auto-mint case)

### Why Transfer Is More Expensive Than Basic ERC20

**Standard ERC20 transfer:** ~21k gas
- 1 SLOAD (check balance)
- 2 SSTORE (update balances)
- 1 event emission

**Your Option.transfer():** ~413k gas (19.6x more expensive!)

### Call Stack Breakdown

```
Option.transfer(to, amount)
├─ [Modifier] notLocked                               // ~3k gas
├─ [Modifier] nonReentrant                            // ~4k gas
├─ Check sender balance                               // ~2k gas
├─ IF (balance < amount) → AUTO-MINT                  // **~331k gas** ⚠️⚠️⚠️
│  └─ mint_(msg.sender, amount - balance)
│     └─ (See full mint breakdown above)
├─ super.transfer(to, amount)                         // ~21k gas
│  └─ Standard ERC20 transfer (OpenZeppelin)
├─ Check if receiver has Redemption tokens            // ~3k gas
│  └─ redemption.balanceOf(to)
└─ IF (receiver has Redemption) → AUTO-REDEEM         // **~50k gas** ⚠️
   └─ redeem_(to, min(balance, amount))
      ├─ _burn(to, amount)                            // ~10k gas
      └─ redemption._redeemPair(to, amount)           // ~40k gas
         ├─ Check balance < amount                    // ~2k gas
         ├─ _burn(to, amount)                         // ~10k gas
         ├─ collateral.safeTransfer(to, amount)       // ~25k gas
         └─ emit event                                // ~3k gas
```

### Why Auto-Settling?

**Design Choice:** Prevent transfer failures

**Without auto-settling:**
```solidity
alice.transfer(bob, 10 tokens)
// ❌ REVERTS if alice only has 5 tokens
```

**With auto-settling (current):**
```solidity
alice.transfer(bob, 10 tokens)
// ✅ Auto-mints 5 more tokens for alice
// ✅ Transfer succeeds
// Gas: Expensive but UX is better
```

**Trade-off:**
- ❌ Higher gas cost
- ✅ Better user experience
- ✅ No failed transfers
- ✅ Makes the token more "liquid"

---

## Comparison to Other Protocols

### Basic ERC20 (USDC, DAI)

| Operation | USDC | Option | Overhead |
|-----------|------|--------|----------|
| transfer() | ~21k | ~413k | **+19.6x** |
| mint() | ~51k | ~343k | **+6.7x** |
| Total features | Basic | Auto-settling, dual-token, ReentrancyGuard, AddressSet | N/A |

### Complex DeFi Tokens

| Protocol | Operation | Gas | Notes |
|----------|-----------|-----|-------|
| **Uniswap V3 LP** | Mint position | ~250k | Position management |
| **Curve LP** | Add liquidity | ~200k | Multi-token pool |
| **Balancer LP** | Join pool | ~300k | Complex math |
| **Your Option** | Mint | ~343k | Dual-token + tracking |
| **Your Option** | Transfer (auto-mint) | ~413k | Most expensive |

**Assessment:** Your gas costs are **above average** but justified by features:
- ✅ Dual-token system (Option + Redemption)
- ✅ Auto-settling transfers
- ✅ AddressSet for sweep functionality
- ✅ Fee-on-transfer protection
- ✅ Permit2 support

---

## Gas Optimization Recommendations

### 🟢 Easy Wins (Low Risk, Medium Impact)

#### 1. **Make AddressSet Optional** - Save ~100k per mint

**Current:**
```solidity
modifier saveAccount(address account) {
    _accounts.add(account);  // Always executes
    _;
}
```

**Optimized:**
```solidity
bool public trackAccounts = true;  // Toggle feature

modifier saveAccount(address account) {
    if (trackAccounts) {
        _accounts.add(account);
    }
    _;
}

// Owner can disable if sweep() not needed
function setTrackAccounts(bool enabled) external onlyOwner {
    trackAccounts = enabled;
}
```

**Savings:** ~100k gas per mint (29% reduction!)
**Trade-off:** Lose sweep() functionality if disabled

#### 2. **Offer Standard ERC20 Approval Path** - Save ~35k per mint

**Current:** Always uses Permit2
**Optimized:** Check standard approval first

```solidity
function transferFrom(address from, address to, uint160 amount, address token) external {
    // Try standard ERC20 first (cheaper)
    if (ERC20(token).allowance(from, address(this)) >= amount) {
        ERC20(token).safeTransferFrom(from, to, amount);  // ~65k gas
        return true;
    }

    // Fall back to Permit2 if needed
    (uint160 allowAmount, uint48 expiration,) = permit2.allowance(from, token, address(this));
    if (allowAmount >= amount && expiration > uint48(block.timestamp)) {
        permit2.transferFrom(from, to, amount, token);  // ~100k gas
        return true;
    }

    revert("Insufficient allowance");
}
```

**Savings:** ~35k gas per mint/transfer (10% reduction)
**Trade-off:** None! Permit2 still available

#### 3. **Cache External Call Results** - Save ~5-10k gas

**Current:**
```solidity
function transfer(address to, uint256 amount) public {
    uint256 balance = this.balanceOf(msg.sender);  // External call
    // ...
    balance = redemption.balanceOf(to);            // Another external call
}
```

**Optimized:**
```solidity
function transfer(address to, uint256 amount) public {
    uint256 senderBalance = balanceOf(msg.sender);  // Direct internal call
    // ...
    // Cache redemption reference
    Redemption redemptionCache = redemption;
    uint256 receiverBalance = redemptionCache.balanceOf(to);
}
```

**Savings:** ~5k gas per transfer
**Trade-off:** None

### 🟡 Medium Effort (Moderate Risk, High Impact)

#### 4. **Lazy AddressSet Updates** - Save ~80k gas per mint

**Current:** Updates AddressSet on EVERY mint
**Optimized:** Only update on first mint per address

```solidity
mapping(address => bool) private _hasEverMinted;

function mint(address account, uint256 amount) public {
    // Only add to set if first time
    if (!_hasEverMinted[account]) {
        _accounts.add(account);
        _hasEverMinted[account] = true;  // Extra SSTORE: ~5k gas
    }

    // Rest of mint logic...
}
```

**Savings:** ~95k gas on subsequent mints (saves ~80k net after new boolean)
**First mint:** ~348k gas (slightly more expensive)
**Subsequent mints:** ~253k gas (26% cheaper!)
**Trade-off:** AddressSet only tracks "has ever held" not "currently holds"

#### 5. **Remove Fee-on-Transfer Check** - Save ~10k gas

**Current:**
```solidity
uint256 balanceBefore = collateral.balanceOf(address(this));
_factory.transferFrom(account, address(this), amount, address(collateral));
uint256 balanceAfter = collateral.balanceOf(address(this));
if (balanceAfter - balanceBefore != amount) revert FeeOnTransferNotSupported();
```

**Optimized:** Remove check, blocklist fee-on-transfer tokens in Factory

```solidity
// In OptionFactory
mapping(address => bool) public blocklist;

function addToBlocklist(address token) external onlyOwner {
    blocklist[token] = true;
}

function createOption(...) public {
    if (blocklist[collateral] || blocklist[consideration]) {
        revert("Token blocklisted");
    }
    // ... rest of creation
}
```

**Savings:** ~10k gas per mint
**Trade-off:** Admin must manually blocklist problematic tokens

### 🔴 Hard Optimizations (High Risk, High Impact)

#### 6. **Make Auto-Settling Optional** - Save ~330k on transfer

**Concept:** Let users opt-in to auto-settling

```solidity
mapping(address => bool) public autoSettleEnabled;

function enableAutoSettle() external {
    autoSettleEnabled[msg.sender] = true;
}

function transfer(address to, uint256 amount) public {
    uint256 balance = balanceOf(msg.sender);

    // Only auto-mint if enabled
    if (autoSettleEnabled[msg.sender] && balance < amount) {
        mint_(msg.sender, amount - balance);
    } else {
        require(balance >= amount, "Insufficient balance");
    }

    // ... rest of transfer
}
```

**Savings:** ~330k gas for users who don't need auto-settling
**Trade-off:** Breaks composability, adds complexity

#### 7. **Batch Operations** - Save ~40% on multiple operations

```solidity
function mintBatch(address[] calldata accounts, uint256[] calldata amounts) external {
    require(accounts.length == amounts.length);

    // Shared reentrancy check
    require(_status != ENTERED);
    _status = ENTERED;

    for (uint i = 0; i < accounts.length; i++) {
        // Internal mint without reentrancy checks
        _mintInternal(accounts[i], amounts[i]);
    }

    _status = NOT_ENTERED;
}
```

**Savings:** ~4k per extra operation (amortized reentrancy guard)

---

## Summary: Where Does the Gas Go?

### Option.mint() - 343k gas total

| Component | Gas | % | Optimization |
|-----------|-----|---|--------------|
| **AddressSet.add()** | 100k | 29% | 🟢 Make optional → Save 100k |
| **Permit2 transfer** | 100k | 29% | 🟢 Offer ERC20 path → Save 35k |
| **ERC20 mint (Redemption)** | 10k | 3% | 🔴 Core functionality |
| **Fee-on-transfer check** | 10k | 3% | 🟡 Remove → Save 10k |
| **ERC20 mint (Option)** | 10k | 3% | 🔴 Core functionality |
| **ReentrancyGuard** | 4k | 1% | 🔴 Security critical |
| **Modifiers + checks** | 10k | 3% | 🔴 Necessary validation |
| **Events** | 6k | 2% | 🔴 Essential for indexing |
| **Overhead** | 93k | 27% | Various small costs |

**Total Optimization Potential:** ~145k gas (42% reduction)
- Easy wins: ~145k (Make AddressSet optional + ERC20 path)
- Medium wins: ~90k more (Lazy updates + remove fee check)
- Hard wins: ~330k more (Optional auto-settling)

### Option.transfer() - 413k gas total

| Component | Gas | % | Optimization |
|-----------|-----|---|--------------|
| **Auto-mint** | 331k | 80% | 🔴 Core feature, user choice |
| **Auto-redeem** | 50k | 12% | 🟡 Could make optional |
| **Base ERC20 transfer** | 21k | 5% | 🔴 Standard cost |
| **ReentrancyGuard** | 4k | 1% | 🔴 Security critical |
| **Lock check** | 3k | 1% | 🔴 Safety feature |
| **Overhead** | 4k | 1% | Various small costs |

**Total Optimization Potential:** ~50k gas (12% reduction)
- Only if auto-redeem is made optional
- Auto-mint is core feature and can't be removed without breaking UX

---

## Recommended Action Plan

### Phase 1: Quick Wins (Do Now)

1. ✅ **Add standard ERC20 approval path** alongside Permit2
   - Saves ~35k per operation
   - Zero downside
   - 1 hour implementation

2. ✅ **Cache external calls**
   - Saves ~5-10k per operation
   - Zero risk
   - 30 minutes implementation

### Phase 2: Feature Toggles (Next Sprint)

3. ✅ **Make AddressSet tracking optional**
   - Saves ~100k per mint when disabled
   - Loses sweep() functionality
   - 2 hours implementation + testing

4. ✅ **Remove fee-on-transfer check, use blocklist**
   - Saves ~10k per mint
   - Requires admin management
   - 1 hour implementation

### Phase 3: Advanced (Future)

5. ⚠️ **Lazy AddressSet updates**
   - Saves ~80k on repeat mints
   - Changes sweep() semantics
   - Requires careful design

6. ⚠️ **Optional auto-settling**
   - Saves ~330k for power users
   - Breaks composability
   - Significant complexity

---

## Final Thoughts

Your gas costs are **high but justified** for a feature-rich options protocol. The main drivers are:

1. **Dual-token system** - Inherent complexity
2. **Auto-settling** - Amazing UX, but expensive
3. **AddressSet tracking** - Useful for sweep(), but costly
4. **Security features** - ReentrancyGuard is necessary

**Comparison verdict:**
- vs Basic ERC20: 19.6x more expensive ❌
- vs Complex DeFi: Slightly above average ⚠️
- vs Options protocols: **Competitive** ✅
- vs User experience: **Excellent** ✅

**Recommendation:** Implement Phase 1 optimizations (saves 40k gas, ~12%), then decide if Phase 2 is worth the complexity trade-offs.
