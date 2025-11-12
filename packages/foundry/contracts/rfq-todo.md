# RFQ.sol Security Audit - Issues to Fix

## Security Audit of RFQ.sol (PriceIntent Contract)

---

## 🔴 **CRITICAL ISSUES**

### 1. **Missing Reentrancy Protection**
**Location:** [RFQ.sol:82](RFQ.sol#L82) (`fill` function)

The `fill()` function performs external token transfers before updating state, violating the Checks-Effects-Interactions pattern:

```solidity
// Lines 114-122: Transfers happen first
IERC20(o.tokenIn).safeTransferFrom(...);
IERC20(o.tokenOut).safeTransferFrom(...);

// Line 124: State updated AFTER transfers
filledIn[o.maker][o.nonce] = already + inAmt;
```

**Attack Vector:** A malicious ERC20 token with a callback could re-enter `fill()` before `filledIn` is updated, allowing the same order to be filled multiple times beyond `maxIn`.

**Recommendation:** Add `ReentrancyGuard` from OpenZeppelin and move state updates before transfers:
```solidity
filledIn[o.maker][o.nonce] = already + inAmt;
emit Filled(digest, o.maker, msg.sender, inAmt, outAmt);

// Then do transfers
if (o.makerSellsIn) { ... }
```

---

### 2. **Fee Loss / Unaccounted Funds**
**Location:** [RFQ.sol:107-111](RFQ.sol#L107-L111)

```solidity
if (o.feeBps > 0) {
    uint256 fee = (outAmt * o.feeBps) / 10_000;
    outAmt -= fee;
    // send fee to some recipient if desired  ← FUNDS LOST
}
```

The fee is deducted from `outAmt` but **never transferred anywhere**. This means:
- The taker receives less than they should
- The fee amount is permanently stuck in the maker's balance or never accounted for
- **This creates an accounting discrepancy**

**Recommendation:** Either remove the fee mechanism entirely or implement proper fee collection with a recipient address.

---

### 3. **Signature Malleability (EIP-2098 Not Enforced)**
**Location:** [RFQ.sol:89](RFQ.sol#L89)

```solidity
address signer = ECDSA.recover(digest, sig);
require(signer == o.maker, "bad sig");
```

While OpenZeppelin's ECDSA.recover has some protections, the contract doesn't explicitly check signature format. An attacker could potentially:
- Submit the same signature with modified `s` value (signature malleability)
- Cause unexpected behavior if signatures are tracked off-chain

**Recommendation:** Use `ECDSA.tryRecover` and check for errors, or add explicit signature format validation.

---

## 🟠 **HIGH-SEVERITY ISSUES**

### 4. **Integer Overflow in Fee Calculation**
**Location:** [RFQ.sol:108](RFQ.sol#L108)

```solidity
uint256 fee = (outAmt * o.feeBps) / 10_000;
```

No validation that `o.feeBps <= 10_000`. A malicious maker could sign an order with `feeBps = 100_000`, causing:
- Fee calculation to exceed `outAmt`
- Underflow on line 109: `outAmt -= fee` (reverts with Solidity 0.8+)
- But this allows **DoS attacks** where orders become unfillable

**Recommendation:** Add validation:
```solidity
require(o.feeBps <= 10_000, "fee > 100%");
```

---

### 5. **Missing Zero-Address Validation**
**Location:** [RFQ.sol:14-27](RFQ.sol#L14-L27) (Order struct)

No validation that `o.tokenIn`, `o.tokenOut`, or `o.maker` are non-zero addresses. This could lead to:
- Orders that send tokens to `address(0)` (permanent loss)
- Signature validation passing with `signer == address(0)` if ECDSA recovery fails silently

**Recommendation:** Add checks:
```solidity
require(o.maker != address(0) && o.tokenIn != address(0) && o.tokenOut != address(0), "zero address");
```

---

### 6. **Price Manipulation via Extreme Values**
**Location:** [RFQ.sol:103-104](RFQ.sol#L103-L104)

```solidity
uint256 outAmt = Math.mulDiv(inAmt, o.price1e18, 1e18, ...);
```

No bounds checking on `o.price1e18`. While `Math.mulDiv` handles overflow safely, extreme prices could cause:
- Orders with `price1e18 = 0` → `outAmt = 0` → free tokens
- Orders with `price1e18 = type(uint256).max` → DoS via overflow

**Recommendation:** Add reasonable bounds:
```solidity
require(o.price1e18 > 0 && o.price1e18 < 1e36, "invalid price");
```

---

## 🟡 **MEDIUM-SEVERITY ISSUES**

### 7. **Deadline Can Be Far Future (No Max Deadline)**
**Location:** [RFQ.sol:83](RFQ.sol#L83)

Orders could have `deadline = type(uint256).max`, making them effectively permanent and uncancellable if the maker loses access to their account.

**Recommendation:** Consider adding a maximum reasonable deadline (e.g., 1 year).

---

### 8. **No Pause Mechanism**
Unlike the main protocol contracts which have a `locked` flag, this RFQ contract has no emergency stop mechanism if a critical bug is discovered.

**Recommendation:** Add `Pausable` from OpenZeppelin.

---

### 9. **EIP-712 Domain Separator Static (No Chain Fork Protection)**
**Location:** [RFQ.sol:44-52](RFQ.sol#L44-L52)

The `DOMAIN_SEPARATOR` is computed once in the constructor. If the chain forks (e.g., Ethereum mainnet → ETH Classic), signatures from one chain could be replayed on the other.

**Recommendation:** Use OpenZeppelin's `EIP712` base contract which handles chain ID updates dynamically.

---

## 🔵 **LOW-SEVERITY / INFORMATIONAL**

### 10. **Gas Inefficiency: Redundant Storage Reads**
Line 97-98 reads `filledIn[o.maker][o.nonce]` but could be optimized.

### 11. **Missing Events for Cancel**
The `cancel` function emits an event but doesn't prevent fills in the same transaction (front-running possible).

### 12. **Contract Name Mismatch**
The contract is named `PriceIntent` but the file is `RFQ.sol` - could cause confusion.

### 13. **No Getter for DOMAIN_SEPARATOR Components**
Off-chain signature creation needs to reconstruct the domain separator; consider adding helper getters.

---

## Summary of Critical Risks

| Issue | Severity | Impact |
|-------|----------|--------|
| Missing reentrancy protection | **CRITICAL** | Order can be overfilled, draining maker funds |
| Fee funds lost | **CRITICAL** | Economic/accounting failure |
| Signature malleability | **CRITICAL** | Potential replay attacks |
| No fee bounds checking | **HIGH** | DoS attacks on orders |
| Zero address not validated | **HIGH** | Token loss |
| Price bounds not checked | **HIGH** | Free tokens or DoS |

---

## Overall Assessment

This contract has **significant security vulnerabilities** and should **NOT be deployed to production** without addressing at least the critical issues. The reentrancy vulnerability is particularly dangerous with malicious ERC20 tokens.

## Next Steps

1. Fix all CRITICAL issues before any deployment
2. Address HIGH-severity issues
3. Write comprehensive tests including:
   - Reentrancy attack simulation
   - Fee calculation edge cases
   - Signature validation tests
   - Zero-address scenarios
4. Consider professional audit before mainnet deployment
