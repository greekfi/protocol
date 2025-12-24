# Options Protocol Security Audit Report

**Audit Date**: 2025-12-24
**Protocol**: Dual-Token Options Protocol (Option.sol, Redemption.sol, OptionFactory.sol)
**Auditor**: Claude Code Security Analysis

---

## Executive Summary

This audit identified **3 CRITICAL**, **5 HIGH**, and **8 MEDIUM** severity issues across the protocol. The most severe issues involve unvalidated fee adjustments, silent failure modes, and unexpected auto-minting behavior that could lead to catastrophic fund loss.

**CRITICAL RISK ISSUES (Immediate Fix Required)**:
1. Unvalidated fee adjustment allows >100% fees
2. Silent failure in redemption modifier
3. Auto-mint in transfer() can drain user funds

---

## CRITICAL SEVERITY ISSUES

### [CRITICAL-1] Unvalidated Fee Adjustment Allows Stealing All Funds

**Location**: `Redemption.sol:503-505`, `Option.sol:591-593`

**Description**: The `adjustFee()` function in Redemption has NO validation, allowing the owner to set fees to any value including >100%. This breaks the unchecked math assumptions.

```solidity
// Redemption.sol:503
function adjustFee(uint64 fee_) public onlyOwner {
    fee = fee_;  // ← NO VALIDATION!
}
```

**Impact**:
- If fee is set to >1e18 (100%), the unchecked subtraction in mint() will underflow:
  ```solidity
  unchecked {
      uint256 fee_ = (amount * fee) / 1e18;  // If fee > 1e18, this could be > amount
      _mint(account, amount - fee_);  // ← UNDERFLOW! Mints ~uint256.max tokens
  }
  ```
- Alternatively, setting fee to 1e18 (100%) means `amount - fee_ = 0`, so no tokens are minted but all collateral is taken as fees
- Owner of Option contract can call this to steal all collateral from future minters

**Proof of Concept**:
```solidity
// Attacker is owner of Option contract
option.adjustFee(2e18);  // Set fee to 200%
// Victim approves and mints 100 WETH
victim.approve(option, 100e18);
option.mint(100e18);
// Unchecked math: amount - fee = 100e18 - 200e18 = underflows to massive number
// Victim receives ~uint256.max Option tokens (breaks everything)
// OR with 100% fee, victim receives 0 tokens but loses 100 WETH
```

**Recommendation**:
```solidity
function adjustFee(uint64 fee_) public onlyOwner {
    require(fee_ <= 0.01e18, "fee exceeds maximum 1%");  // Match OptionFactory.MAX_FEE
    fee = fee_;
}
```

**Severity**: CRITICAL - Complete fund loss or protocol break

---

### [CRITICAL-2] Silent Failure in sufficientBalance Modifier

**Location**: `Redemption.sol:144-147`

**Description**: The `sufficientBalance` modifier uses `return` instead of `revert`, causing functions to silently succeed without executing.

```solidity
modifier sufficientBalance(address account, uint256 amount) {
    if (balanceOf(account) < amount) return;  // ← SHOULD REVERT!
    _;
}
```

**Impact**:
- Used in `_redeem()` at line 324
- If user has insufficient balance, `_redeem()` returns successfully without doing anything
- No tokens burned, no collateral sent, no error thrown
- User thinks redemption succeeded when it actually failed
- Silent failures are extremely dangerous for UX and composability
- Could cause accounting errors in integrating protocols

**Proof of Concept**:
```solidity
// User has 10 Redemption tokens, tries to redeem 100
redemption.redeem(alice, 100);
// Returns success, but nothing happens
// alice.balance unchanged, alice.collateral unchanged
// No revert, no event, silent failure
```

**Recommendation**:
```solidity
modifier sufficientBalance(address account, uint256 amount) {
    if (balanceOf(account) < amount) revert InsufficientBalance();
    _;
}
```

**Severity**: CRITICAL - Silent failures break composability and user expectations

---

### [CRITICAL-3] Auto-Mint in transfer() Can Drain User Funds

**Location**: `Option.sol:442-462`

**Description**: The `transfer()` function automatically mints new Option tokens if the sender doesn't have enough, pulling collateral from their account. This is extremely dangerous.

```solidity
function transfer(address to, uint256 amount) public ... {
    uint256 balance = balanceOf(msg.sender);
    if (balance < amount) {
        mint_(msg.sender, amount - balance);  // ← AUTO-MINTS if insufficient!
    }
    success = super.transfer(to, amount);
    // ...
}
```

**Impact**:
- User fat-fingers a transfer amount (types 10000 instead of 100)
- Contract silently mints 9900 new tokens, pulling 9900 collateral from user's account
- User loses massive amounts of collateral due to typo
- No confirmation, no warning, just instant fund drain
- Vulnerable to UI bugs that set incorrect amounts
- Breaks user expectations of ERC20 transfer behavior

**Proof of Concept**:
```solidity
// Alice has 100 Option tokens, 10000 WETH approved
// Alice tries to transfer 100 but UI bug sends 10000
option.transfer(bob, 10000);
// Contract mints 9900 new tokens, pulling 9900 WETH from Alice
// Alice intended to send $200k but accidentally sent $20M
```

**Recommendation**:
Remove auto-mint entirely or add explicit opt-in:
```solidity
function transfer(address to, uint256 amount) public ... {
    uint256 balance = balanceOf(msg.sender);
    if (balance < amount) {
        revert InsufficientBalance();  // Normal ERC20 behavior
    }
    // ... rest of function
}

// Add separate function for auto-mint behavior
function transferOrMint(address to, uint256 amount) public {
    // Explicit opt-in to auto-mint behavior
}
```

**Severity**: CRITICAL - Catastrophic fund loss from typos or UI bugs

---

## HIGH SEVERITY ISSUES

### [HIGH-1] Premature Consideration Redemption Before Expiration

**Location**: `Redemption.sol:349-361`

**Description**: `redeemConsideration()` has no `expired` modifier, allowing Redemption token holders to redeem for consideration before expiration, breaking the options model.

```solidity
function redeemConsideration(uint256 amount) public notLocked {  // ← No 'expired' modifier!
    redeemConsideration(msg.sender, amount);
}
```

**Impact**:
- Option holders exercise, paying consideration and receiving collateral
- Redemption holders can immediately redeem for that consideration before expiration
- This depletes the consideration pool that should back the remaining collateral value
- Breaks the fundamental options model where Redemption tokens are claims on collateral
- Redemption holders can "cut in line" to extract value early

**Proof of Concept**:
```solidity
// 1. Alice mints 100 Option+Redemption pairs (deposits 100 WETH)
option.mint(100e18);  // Alice has 100 Option, 100 Redemption

// 2. Bob exercises 50 Options (pays 100k USDC @ 2000 strike, gets 50 WETH)
option.exercise(50e18);
// Contract: 50 WETH collateral, 100k USDC consideration

// 3. Alice calls redeemConsideration BEFORE EXPIRATION
redemption.redeemConsideration(50e18);
// Alice receives 100k USDC (equivalent to 50 WETH at strike)
// Alice has now extracted full value before expiration!

// 4. Remaining 50 Redemption holders expect 50 WETH but only 50 WETH remains
// Value properly backed, but Alice got liquidity before expiration unfairly
```

**Recommendation**:
```solidity
function redeemConsideration(uint256 amount) public expired notLocked {  // Add 'expired'
    redeemConsideration(msg.sender, amount);
}

function redeemConsideration(address account, uint256 amount)
    public
    expired  // Add here too
    notLocked
    nonReentrant
{
    _redeemConsideration(account, amount);
}
```

**Severity**: HIGH - Breaks options model, allows unfair early extraction

---

### [HIGH-2] Downcasting to uint160 Causes Silent Truncation

**Location**: `OptionFactory.sol:156`, `Redemption.sol:257`, `Redemption.sol:400`

**Description**: Transfer amounts are downcast from uint256 to uint160, causing silent truncation for large amounts.

```solidity
// OptionFactory.sol:156
function transferFrom(address from, address to, uint160 amount, address token)

// Redemption.sol:257
_factory.transferFrom(account, address(this), uint160(amount), address(collateral));
```

**Impact**:
- If user tries to mint/exercise with amount > type(uint160).max (≈ 1.46e48), it silently truncates
- For 18-decimal tokens: uint160.max ≈ 1.46e30 tokens (e.g., 1.46 billion ETH)
- For lower-decimal tokens or with very large supplies, this could be realistic
- User approves and expects to transfer X, but only X % 2^160 is transferred
- No revert, silent data loss

**Recommendation**:
```solidity
// OptionFactory.sol
function transferFrom(address from, address to, uint256 amount, address token)
    external nonReentrant returns (bool success)
{
    if (!redemptions[msg.sender]) revert InvalidAddress();
    if (allowance(token, from) < amount) revert InvalidAddress();
    require(amount <= type(uint160).max, "amount too large");  // Explicit check
    ERC20(token).safeTransferFrom(from, to, amount);
    return true;
}
```

**Severity**: HIGH - Silent fund loss for large amounts

---

### [HIGH-3] Rounding in toConsideration/toCollateral Always Favors Protocol

**Location**: `Redemption.sol:470-496`

**Description**: Both conversion functions use Math.mulDiv which rounds DOWN, consistently favoring the protocol over users.

```solidity
function toConsideration(uint256 amount) public view returns (uint256) {
    uint256 consMultiple = Math.mulDiv(
        (10 ** consDecimals),
        strike,
        (10 ** STRIKE_DECIMALS) * (10 ** collDecimals)
    );  // ← Rounds down

    (uint256 high, uint256 low) = Math.mul512(amount, consMultiple);
    return low;  // ← User receives LESS consideration
}
```

**Impact**:
- When exercising, users pay slightly LESS consideration than they should (rounding down)
- When redeeming for consideration, users receive slightly LESS than they should (rounding down)
- Over many operations, dust accumulates in contract
- For small amounts or extreme decimal differences, rounding could be significant
- Example: 1 wei collateral might convert to 0 consideration

**Recommendation**:
Add rounding modes and be explicit:
```solidity
function toConsideration(uint256 amount, bool roundUp) public view returns (uint256) {
    if (roundUp) {
        // Use Math.mulDiv with rounding up for user-favorable operations
        return Math.mulDiv(amount, consMultiple, 1, Math.Rounding.Ceil);
    } else {
        return Math.mulDiv(amount, consMultiple, 1, Math.Rounding.Floor);
    }
}

// Exercise: round UP consideration required (user pays more, protocol protected)
// Redeem: round DOWN consideration sent (protocol keeps dust)
```

**Severity**: HIGH - Consistent value leak from users

---

### [HIGH-4] Auto-Redeem in transferFrom May Be Unexpected

**Location**: `Option.sol:414-426`

**Description**: When Option tokens are transferred, if the recipient holds Redemption tokens, they are automatically redeemed. This may be unwanted.

```solidity
function transferFrom(address from, address to, uint256 amount) public ... {
    success = super.transferFrom(from, to, amount);
    uint256 balance = redemption.balanceOf(to);
    if (balance > 0) {
        redeem_(to, min(balance, amount));  // ← Auto-redeems recipient's position
    }
}
```

**Impact**:
- Recipient may want to hold both Option and Redemption tokens for liquidity provision
- Automatic redemption closes their position without consent
- Could cause issues with DEX liquidity pools or option market makers
- Breaks composability with DeFi protocols that expect normal ERC20 behavior

**Recommendation**:
Make auto-redeem opt-in:
```solidity
mapping(address => bool) public autoRedeemEnabled;

function enableAutoRedeem() external {
    autoRedeemEnabled[msg.sender] = true;
}

function transferFrom(address from, address to, uint256 amount) public ... {
    success = super.transferFrom(from, to, amount);
    if (autoRedeemEnabled[to]) {
        uint256 balance = redemption.balanceOf(to);
        if (balance > 0) {
            redeem_(to, min(balance, amount));
        }
    }
}
```

**Severity**: HIGH - Breaks composability and user autonomy

---

### [HIGH-5] Unchecked Math Relies on Fee Validation That Doesn't Exist

**Location**: `Option.sol:397-401`, `Redemption.sol:265-269`

**Description**: Code uses `unchecked` blocks with comment "max fee is 1%, can't overflow", but fee validation is missing in Redemption.adjustFee().

```solidity
// Option.sol:397
unchecked {
    uint256 amountMinusFees = amount - ((amount * fee) / 1e18);  // ← Assumes fee <= 0.01e18
    _mint(account, amountMinusFees);
}
```

**Impact**:
- Comment assumes fee <= 1%, but this is not enforced in Redemption
- If fee > 1e18, the subtraction underflows
- Results in minting massive amounts of tokens or taking all collateral
- See CRITICAL-1 for full impact

**Recommendation**:
Either remove unchecked or add validation (covered in CRITICAL-1)

**Severity**: HIGH - Arithmetic underflow if fee validation missing

---

## MEDIUM SEVERITY ISSUES

### [MEDIUM-1] Missing Events in Critical State Changes

**Location**: `OptionFactory.sol:183-186`

**Description**: The `approve()` function doesn't emit an event, making it hard to track allowances off-chain.

```solidity
function approve(address token, uint256 amount) public {
    if (token == address(0)) revert InvalidAddress();
    _allowances[token][msg.sender] = amount;  // ← No event
}
```

**Recommendation**:
```solidity
event Approval(address indexed token, address indexed owner, uint256 amount);

function approve(address token, uint256 amount) public {
    if (token == address(0)) revert InvalidAddress();
    _allowances[token][msg.sender] = amount;
    emit Approval(token, msg.sender, amount);
}
```

**Severity**: MEDIUM - Reduces transparency

---

### [MEDIUM-2] Expiration Can Be Set to Current Timestamp

**Location**: `Redemption.sol:222`

**Description**: Initialization allows `expirationDate_ == block.timestamp`, creating immediately-expired options.

```solidity
if (expirationDate_ < block.timestamp) revert InvalidValue();  // ← Should be <=
```

**Recommendation**:
```solidity
if (expirationDate_ <= block.timestamp) revert InvalidValue();
```

**Severity**: MEDIUM - Creates useless options

---

### [MEDIUM-3] No Validation of Strike Price

**Location**: `Redemption.sol:221`

**Description**: Strike price can be set to extreme values (1 wei or uint256.max) without validation.

```solidity
if (strike_ == 0) revert InvalidValue();  // ← Only checks for 0
```

**Impact**:
- Strike = 1 wei means options are essentially free
- Strike = uint256.max causes numerical issues in toConsideration()
- Could break conversion functions

**Recommendation**:
```solidity
if (strike_ == 0 || strike_ > 1e36) revert InvalidValue();  // Reasonable upper bound
```

**Severity**: MEDIUM - Can create broken options

---

### [MEDIUM-4] claimFees Can Be Called By Anyone

**Location**: `OptionFactory.sol:235-241`, `Option.sol:599-601`

**Description**: Anyone can trigger fee collection to the owner, wasting gas.

```solidity
function claimFees(address[] memory tokens) public nonReentrant {  // ← No access control
    for (uint256 i = 0; i < tokens.length; i++) {
        // ...
    }
}
```

**Impact**:
- Griefer can call this repeatedly to waste gas
- Owner might prefer to batch fee claims
- Minor gas waste, no fund loss

**Recommendation**:
```solidity
function claimFees(address[] memory tokens) public onlyOwner nonReentrant {
```

**Severity**: MEDIUM - Gas griefing

---

### [MEDIUM-5] Unbounded Loop in Sweep Function

**Location**: `Redemption.sol:421-429`

**Description**: `sweep(address[])` has unbounded loop that could run out of gas.

```solidity
function sweep(address[] calldata holders) public expired notLocked nonReentrant {
    for (uint256 i = 0; i < holders.length; i++) {  // ← No limit
        // ...
    }
}
```

**Impact**:
- Large arrays cause out-of-gas
- Only affects caller, not protocol
- Self-DoS attack

**Recommendation**:
```solidity
function sweep(address[] calldata holders) public expired notLocked nonReentrant {
    require(holders.length <= 100, "batch too large");
    for (uint256 i = 0; i < holders.length; i++) {
        // ...
    }
}
```

**Severity**: MEDIUM - DoS for caller only

---

### [MEDIUM-6] Confusing Dual Approval System

**Location**: `OptionFactory.sol:156-166`, `OptionFactory.sol:183-186`

**Description**: Factory has internal `_allowances` mapping separate from ERC20 approvals, creating confusion.

**Impact**:
- Users must call `factory.approve(token, amount)` NOT `token.approve(factory, amount)`
- This is non-standard and confusing
- Users might approve the wrong contract
- Could lead to failed transactions

**Recommendation**:
Use standard ERC20 approvals or document this very clearly:
```solidity
// Better: Remove internal allowances and just use SafeERC20.safeTransferFrom
// which will use standard ERC20 approvals
```

**Severity**: MEDIUM - UX confusion

---

### [MEDIUM-7] No Validation of Token Addresses in createOption

**Location**: `OptionFactory.sol:109-130`

**Description**: `createOption()` doesn't validate that collateral/consideration are actually ERC20 tokens.

```solidity
function createOption(address collateral, address consideration, ...) public ... {
    if (blocklist[collateral] || blocklist[consideration]) revert BlocklistedToken();
    if (collateral == consideration) revert InvalidTokens();
    // ← No check if these are valid ERC20 contracts
```

**Impact**:
- If attacker passes non-ERC20 addresses, calls to decimals() in Redemption.init() will revert
- This just causes init to fail, no fund loss
- Could create options with invalid tokens that immediately fail

**Recommendation**:
```solidity
require(IERC20Metadata(collateral).decimals() <= 77, "invalid collateral");
require(IERC20Metadata(consideration).decimals() <= 77, "invalid consideration");
```

**Severity**: MEDIUM - Creates unusable options

---

### [MEDIUM-8] Duplicate Code in Multiple String Conversion Functions

**Location**: `Option.sol:189-320`, `Redemption.sol:620-751`

**Description**: String conversion functions (uint2str, strike2str, epoch2str, isLeapYear) are duplicated in both contracts.

**Impact**:
- Increases deployment cost
- Harder to maintain
- If bug found in one, must fix in both

**Recommendation**:
Move to a shared library:
```solidity
library StringUtils {
    function uint2str(uint256 _i) internal pure returns (string memory) { ... }
    function strike2str(uint256 _i) internal pure returns (string memory) { ... }
    function epoch2str(uint256 _i) internal pure returns (string memory) { ... }
}
```

**Severity**: MEDIUM - Code quality, gas costs

---

## Summary of Recommendations

### Immediate Actions Required (CRITICAL):
1. **Add fee validation** to `Redemption.adjustFee()` and `Option.adjustFee()`
2. **Fix sufficientBalance modifier** to revert instead of return
3. **Remove or restrict auto-mint** in `Option.transfer()`

### High Priority (HIGH):
4. Add `expired` modifier to `redeemConsideration()` functions
5. Fix uint160 downcasting to uint256 with validation
6. Document rounding behavior or add rounding mode parameters
7. Make auto-redeem opt-in instead of automatic
8. Validate fee in unchecked blocks

### Medium Priority (MEDIUM):
9. Add events for all state changes
10. Prevent expiration == block.timestamp
11. Validate strike price bounds
12. Restrict claimFees to owner
13. Add bounds to sweep array
14. Simplify approval system or document clearly
15. Validate token addresses
16. Deduplicate code

---

## Positive Security Findings

The audit also found several security-positive patterns:

✅ **ReentrancyGuard on all state-changing functions**
✅ **SafeERC20 for all token transfers**
✅ **Fee-on-transfer token detection in mint()**
✅ **Overflow protection with Math.mul512 in conversions**
✅ **Checks-Effects-Interactions pattern mostly followed**
✅ **Proper use of Ownable for access control**
✅ **Initializer protection on clone contracts**

---

## Conclusion

While the protocol demonstrates good security practices in many areas, the CRITICAL issues must be addressed immediately before any mainnet deployment. The unvalidated fee adjustment and auto-mint behavior could lead to complete fund loss. After addressing these issues, a follow-up audit is recommended.

**Risk Rating**: HIGH - Multiple critical issues requiring immediate remediation

