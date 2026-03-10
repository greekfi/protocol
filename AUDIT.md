# Security Audit Report - Greek Protocol

**Date:** 2026-03-09
**Scope:** `foundry/contracts/` (Option.sol, Redemption.sol, OptionFactory.sol, OpHook.sol, OptionPoolVault.sol, OptionPrice.sol, BatchMinter.sol)
**Methodology:** 7 parallel audit tracks -- Access Control, Reentrancy/State, Math/Decimals, Economic/Game Theory, Proxy/Upgrades, External Integrations, ERC20 Compliance/Edge Cases

---

## Summary

| Severity | Count |
|----------|-------|
| CRITICAL | 2 |
| HIGH | 12 |
| MEDIUM | 16 |
| LOW | 16 |
| INFO | 12 |
| **Total** | **58** |

---

## CRITICAL

### C-1: OpHook.initPool() has no access control
- [ ] **Fixed**
- **File:** `OpHook.sol:initPool()` (line 346)
- **Description:** `initPool()` is `public` with no `onlyOwner` modifier. Anyone can register arbitrary option pools, overwrite `collateralPricePool` mappings for any collateral, push unlimited entries into `allPools`, and trigger `type(uint256).max` ERC20 approvals to attacker-controlled factories.
- **Impact:** An attacker can redirect price oracles for existing collateral to manipulated pools, register malicious option contracts, and DoS `getPrices()` by bloating `allPools`.
- **Fix:** Add `onlyOwner` modifier to `initPool()`. Also validate that `optionToken` is registered with a trusted factory.

### C-2: OpHook uses spot price instead of TWAP -- flash loan manipulable
- [ ] **Fixed**
- **File:** `OpHook.sol:getCollateralPrice()` (line 310)
- **Description:** `getCollateralPrice()` reads `slot0().sqrtPriceX96` (instantaneous spot price) from the Uniswap v3 pool, not a TWAP. Spot prices are trivially manipulable within a single transaction using flash loans.
- **Impact:** Attacker flash-loans tokens, moves the v3 spot price, swaps on the v4 hook at a distorted price, reverses the v3 swap, and profits.
- **Fix:** Use Uniswap v3 TWAP via `observe()` instead of `slot0()`.

---

## HIGH

### H-1: Option transfers revert after expiration when recipient holds Redemption tokens
- [ ] **Fixed**
- **File:** `Option.sol:transfer()` (line 530-534), `transferFrom()` (line 495-498)
- **Description:** Both transfer functions call `redeem_()` when the recipient holds Redemption tokens. `redeem_()` has a `notExpired` modifier. After expiration, ALL transfers to any recipient holding Redemption tokens revert.
- **Impact:** Option tokens become non-transferable post-expiration for many recipients. Breaks DEX pools, wallet transfers, and composability.
- **Fix:**
  ```solidity
  if (balance > 0 && block.timestamp < expirationDate()) {
      redeem_(to, min(balance, amount));
  }
  ```

### H-2: Option.transfer() auto-mint breaks ERC20 standard
- [ ] **Fixed**
- **File:** `Option.sol:transfer()` (line 520-522)
- **Description:** `transfer()` auto-mints Option tokens (pulling collateral) when the sender's balance is insufficient, instead of reverting as ERC20 requires. Any integrated protocol (DEX, lending, aggregator) calling `transfer()` may have collateral silently drained.
- **Impact:** Silent fund drain from any contract that interacts with Option tokens via standard ERC20 `transfer()`.
- **Fix:** Remove auto-mint from `transfer()`. Provide a separate `mintAndTransfer()` function.

### H-3: Auto-redeem in transfer burns recipient tokens without consent
- [ ] **Fixed**
- **File:** `Option.sol:transfer()` (line 530-534), `transferFrom()` (line 495-498)
- **Description:** When Option tokens are transferred to a recipient holding Redemption tokens, the recipient's Redemption tokens are burned and collateral is returned -- without their consent. Anyone can force-close another user's short position by sending them Option tokens.
- **Impact:** Forced position closure via griefing. DEX pools holding Redemption tokens would have liquidity destroyed.
- **Fix:** Make auto-redeem opt-in via a separate function or flag.

### H-4: Redemption.redeemConsideration() callable pre-expiration by anyone for any account
- [ ] **Fixed**
- **File:** `Redemption.sol:redeemConsideration(address, uint256)` (line 335)
- **Description:** No `expired` modifier and no caller restriction. Anyone can burn another user's Redemption tokens and send them consideration at any time, even pre-expiration. This bypasses the paired Option/Redemption redemption requirement.
- **Impact:** Force-close another user's short position at unfavorable timing. Pre-expiration consideration drain affects other Redemption holders who expect that consideration post-expiry.
- **Fix:** Restrict to self-redemption (`require(account == msg.sender)`) and/or add `expired` modifier.

### H-5: First-redeemer advantage in post-expiration redemption
- [ ] **Fixed**
- **File:** `Redemption.sol:_redeem()` (line 299-315)
- **Description:** Post-expiration redemption uses a first-come-first-served waterfall (collateral first, then consideration). When both assets exist in the contract, the first redeemer gets collateral and later redeemers get consideration. If the collateral has appreciated, early redeemers extract more value.
- **Impact:** MEV bots can front-run other redeemers. `sweep()` array ordering determines who gets the more valuable asset. Unfair distribution.
- **Fix:** Implement pro-rata distribution: each redeemer receives `(amount / totalSupply) * collateralBalance` collateral AND `(amount / totalSupply) * considerationBalance` consideration simultaneously.

### H-6: Zero-amount exercise extracts collateral for free
- [ ] **Fixed**
- **File:** `Redemption.sol:exercise()` (line 366-383), `toConsideration()` (line 452)
- **Description:** `toConsideration()` uses `Math.mulDiv` which rounds down. For small exercise amounts with large decimal mismatches (e.g., 1 wei WETH at strike 2000e18 with 6-decimal USDC), `toConsideration(1) = 0`. The exerciser pays 0 consideration and receives 1 wei collateral. No check that `consAmount > 0`.
- **Impact:** Free extraction of dust collateral. Gas makes this unprofitable for standard pairs, but it's a protocol correctness bug.
- **Fix:** Add `if (consAmount == 0) revert InvalidValue();` in `exercise()`. Also consider using `Math.Rounding.Ceil` in `toConsideration()`.

### H-7: Redemption.claimFees() -- CEI violation
- [ ] **Fixed**
- **File:** `Redemption.sol:claimFees()` (line 418-421)
- **Description:** Transfers collateral to factory before setting `fees = 0`. If collateral has transfer hooks, `fees` is stale during the callback. `_redeem()` reads `collateral.balanceOf(address(this)) - fees` -- stale `fees` inflates apparent collateral.
- **Impact:** With hook-bearing collateral tokens, re-entrant calls could see inflated collateral balance, enabling over-redemption.
- **Fix:**
  ```solidity
  uint256 feesToClaim = fees;
  fees = 0;
  collateral.safeTransfer(address(_factory), feesToClaim);
  ```

### H-8: Template contracts (Option, Redemption) do not disable initializers
- [ ] **Fixed**
- **File:** `Option.sol` constructor (line 101), `Redemption.sol` constructor (line 157)
- **Description:** Neither template constructor calls `_disableInitializers()`. Anyone can call `init()` on the template contracts, gaining ownership. While clones have independent storage, tokens accidentally sent to templates could be stolen.
- **Fix:** Add `_disableInitializers()` to both constructors.

### H-9: No slippage protection on OpHook swaps
- [ ] **Fixed**
- **File:** `OpHook.sol:_beforeSwap()`, `swapForOption()`
- **Description:** Neither the v4 hook path nor `swapForOption()` implements minimum output checks. Users have no protection against oracle manipulation or price changes between submission and execution.
- **Fix:** Add `minAmountOut` parameter to `swapForOption()`.

### H-10: No ERC4626 inflation attack protection on OptionPoolVault
- [ ] **Fixed**
- **File:** `OptionPoolVault.sol`
- **Description:** Default OZ ERC4626 without virtual shares/assets offset. Classic first-depositor attack: deposit 1 wei, donate large amount directly, steal from subsequent depositors via rounding.
- **Fix:** Override `_decimalsOffset()` to return at least 3.

### H-11: OptionPrice -- no bounds on volatility/risk-free rate; zero vol causes DoS
- [ ] **Fixed**
- **File:** `OptionPrice.sol:setVolatility()` (line 32), `setRiskFreeRate()` (line 37)
- **Description:** No upper/lower bounds. `volatility = 0` causes division-by-zero in `blackScholesPrice()` at `div18(lnks + mu, sigmaSqrtT)` where `sigmaSqrtT = 0`.
- **Fix:** `require(volatility_ >= 0.01e18 && volatility_ <= 10e18)`.

### H-12: OpHook cannot mint options -- fundamental collateral gap
- [ ] **Fixed**
- **File:** `OpHook.sol:_beforeSwap()` (line 262), `swapForOption()` (line 226)
- **Description:** The hook collects cash (USDC) but needs collateral (WETH) to mint options. No mechanism exists to convert cash to collateral or for LPs to deposit collateral. `option.mint()` will fail unless someone independently deposits collateral.
- **Fix:** Implement a collateral deposit function for LPs or integrate with OptionPoolVault.

---

## MEDIUM

### M-1: Redemption._redeemPair() lacks nonReentrant guard
- [ ] **Fixed**
- **File:** `Redemption.sol:_redeemPair()` (line 287)
- **Description:** Callable only by Option (onlyOwner) but has no `nonReentrant`. Calls `_redeem()` which makes external calls. Defense relies on call-chain composition rather than explicit guard.
- **Fix:** Add `nonReentrant` modifier.

### M-2: Cross-contract reentrancy -- independent guards per clone
- [ ] **Fixed**
- **File:** `Option.sol`, `Redemption.sol`, `OptionFactory.sol`
- **Description:** Each clone has its own transient storage reentrancy slot. A malicious token callback during one clone's operation could trigger operations on a different clone.
- **Mitigating factor:** `Factory.transferFrom()` has `nonReentrant` which acts as a global mutex for all token movements. Direct transfers in `_redeem()` bypass this bottleneck.
- **Fix:** Document Factory.transferFrom() as the global reentrancy barrier. Consider adding checks to direct transfer paths.

### M-3: Fee-on-transfer check missing in exercise path
- [ ] **Fixed**
- **File:** `Redemption.sol:exercise()` (line 366-383)
- **Description:** `mint()` checks for fee-on-transfer tokens, but `exercise()` does not check the consideration token. A fee-on-transfer consideration token would cause under-collateralization.
- **Fix:** Add balance-before/after check for consideration in `exercise()`.

### M-4: renounceOwnership() can permanently brick a locked Option contract
- [ ] **Fixed**
- **File:** `Option.sol` (inherits `Ownable`)
- **Description:** If the owner locks the contract then renounces ownership, all operations (transfer, mint, exercise, redeem) are permanently blocked. Collateral is locked forever.
- **Fix:** Override `renounceOwnership()` to revert, or require the contract is unlocked before renouncing.

### M-5: OptionFactory.claimFees() functions have no access control
- [ ] **Fixed**
- **File:** `OptionFactory.sol:claimFees()` (line 276, 285, 297)
- **Description:** All three `claimFees` variants are public with no `onlyOwner`. Anyone can trigger fee transfers to the owner at arbitrary times.
- **Fix:** Add `onlyOwner` or accept as intentional permissionless claiming.

### M-6: OpHook Pausable inherited but pause/unpause never exposed
- [ ] **Fixed**
- **File:** `OpHook.sol`
- **Description:** Inherits `Pausable` but never exposes `pause()` / `unpause()`. Also, `_beforeSwap()` has no `whenNotPaused` check. The emergency pause feature is completely inoperable.
- **Fix:** Add `pause()` / `unpause()` owner functions and `whenNotPaused` to `_beforeSwap()`.

### M-7: Permit2 declared but never used
- [ ] **Fixed**
- **File:** `OpHook.sol` (line 87), `OptionFactory.sol`
- **Description:** `PERMIT2` immutable set in OpHook constructor but never called. Factory uses its own allowance system, not Permit2. Creates false assumptions about the approval model.
- **Fix:** Either implement Permit2 or remove all references.

### M-8: OpHook._beforeAddLiquidity and _beforeDonate possible signature mismatch
- [ ] **Fixed**
- **File:** `OpHook.sol:_beforeAddLiquidity()` (line 278), `_beforeDonate()` (line 286)
- **Description:** Both accept `SwapParams` but BaseHook uses `ModifyLiquidityParams` and `uint256, uint256` respectively. If these don't properly override parent functions, liquidity addition and donation are not actually blocked.
- **Fix:** Verify correct function signatures against the BaseHook version.

### M-9: OpHook._beforeSwap() no reentrancy protection in hook callback
- [ ] **Fixed**
- **File:** `OpHook.sol:_beforeSwap()` (line 240)
- **Description:** Called internally by PoolManager. During `option.mint()`, a malicious collateral token could callback to `OpHook.swapForOption()` which has `nonReentrant` -- but OpHook's guard is NOT set since `_beforeSwap` is internal.
- **Fix:** Add manual reentrancy flag for hook callbacks.

### M-10: OpHook initPool grants irrevocable max approvals
- [ ] **Fixed**
- **File:** `OpHook.sol:initPool()` (line 387-388)
- **Description:** Grants `type(uint256).max` ERC20 approval and `type(uint160).max` factory approval for collateral. No revocation mechanism. If factory is compromised via UUPS upgrade, all hook collateral is at risk.
- **Fix:** Approve only necessary amounts per operation, or add owner-only revocation function.

### M-11: Redemption._redeem() balance relies on balanceOf() not internal tracking
- [ ] **Fixed**
- **File:** `Redemption.sol:_redeem()` (line 300)
- **Description:** `balance = collateral.balanceOf(address(this)) - fees` uses live balance. Direct token transfers inflate available collateral; negative rebasing tokens cause insolvency.
- **Fix:** Consider internal balance tracking. Document that rebasing/deflationary tokens are unsupported.

### M-12: OptionPrice.blackScholesPrice() underflow reverts
- [ ] **Fixed**
- **File:** `OptionPrice.sol:blackScholesPrice()` (line 109, 115)
- **Description:** Unsigned subtraction for call/put prices. Approximation errors in `normCdf()`, `expNeg()`, `ln()` can cause the second term to exceed the first, causing revert for deep OTM options.
- **Fix:** Use saturating subtraction: `price = term1 > term2 ? term1 - term2 : 0;`

### M-13: OpHook.swapForOption() auto-mint side effect from Option.transfer()
- [ ] **Fixed**
- **File:** `OpHook.sol:swapForOption()` (line 227)
- **Description:** After minting, calls `option.transfer(to, p.optionAmount)`. If fees reduced the minted amount, the transfer triggers auto-mint for the deficit, pulling extra collateral from the hook. Also mints unwanted Redemption tokens to the hook.
- **Fix:** Track actual minted amount (balance before/after) and transfer only that. (Already done in `_beforeSwap` but not in `swapForOption`.)

### M-14: OptionFactory.approve() missing Approval event
- [ ] **Fixed**
- **File:** `OptionFactory.sol:approve()` (line 207-209)
- **Description:** Sets allowances without emitting events. Off-chain indexers cannot track allowance changes.
- **Fix:** Add and emit an `Approval` event.

### M-15: Double fee deduction on mint -- both Option and Redemption deduct independently
- [ ] **Fixed**
- **File:** `Option.sol:mint_()` (line 457-465), `Redemption.sol:mint()` (line 216-245)
- **Description:** Both contracts independently deduct fees from their mint amounts. The accounting is internally consistent (990 of each for 1000 deposited at 1% fee), but the double deduction may confuse users. The collateral fee is charged once; the reduced token supply is applied twice.
- **Fix:** Document clearly that fee reduces both token supplies equally. Consider whether this is intended.

### M-16: OptionPrice normCdf lookup table limited to |x| < 5.0
- [ ] **Fixed**
- **File:** `OptionPrice.sol:normCdfPositive()` (line 387-511)
- **Description:** For |x| >= 5.0, returns exactly 1.0 or 0.0. Extreme market conditions can push d1/d2 beyond this range, causing pricing discontinuities.
- **Fix:** Document the valid range. Consider extending tables or reverting for out-of-range inputs.

---

## LOW

### L-1: Redemption.redeem(address) / sweep() allows forced post-expiry redemption
- [ ] **Fixed**
- **File:** `Redemption.sol:redeem(address)` (line 257), `sweep()` (line 392, 402)
- **Description:** Anyone can force-redeem another user's Redemption tokens post-expiry. Documented as intentional. Combined with H-5, the sweep array ordering determines who gets the more valuable asset.

### L-2: Clone init race condition (mitigated by atomic transaction)
- [ ] **Fixed**
- **File:** `OptionFactory.sol:createOption()` (line 134-143)
- **Description:** Between `Clones.clone()` and `init()`, clones are uninitialized. Safe because both happen atomically in `createOption()`.

### L-3: OptionPrice manual owner pattern -- no transfer capability
- [ ] **Fixed**
- **File:** `OptionPrice.sol` (line 28-30)
- **Description:** Uses manual `owner` variable with no `transferOwnership()`. If deployer key is lost, volatility/riskFreeRate are permanently frozen.
- **Fix:** Use OZ `Ownable` or `Ownable2Step`.

### L-4: Factory fee vs Option fee -- factory fee changes don't propagate
- [ ] **Fixed**
- **File:** `OptionFactory.sol:adjustFee()` (line 307), `Option.sol:adjustFee()` (line 668)
- **Description:** Factory `adjustFee()` only affects newly created options. Existing options keep their original fee. No global fee update mechanism.

### L-5: Option.init() does not validate fee <= MAXFEE
- [ ] **Fixed**
- **File:** `Option.sol:init()` (line 115-121)
- **Description:** Accepts fee without checking against `MAXFEE`. In normal flow, factory controls the value, but defense-in-depth is missing.
- **Fix:** Add `if (fee_ > MAXFEE) revert InvalidValue();`

### L-6: Redemption.init() does not validate option_ parameter
- [ ] **Fixed**
- **File:** `Redemption.sol:init()` (line 179-205)
- **Description:** Does not check `option_ != address(0)`. Zero address would permanently lock all `onlyOwner` functions.
- **Fix:** Add `if (option_ == address(0)) revert InvalidAddress();`

### L-7: Unchecked arithmetic in fee calculations
- [ ] **Fixed**
- **File:** `Redemption.sol:mint()` (line 240-244), `Option.sol:mint_()` (line 460-464)
- **Description:** `unchecked` blocks for fee math. Currently safe due to MAXFEE constraint, but fragile if constraints change.
- **Fix:** Consider removing `unchecked` -- gas savings are minimal.

### L-8: OptionFactory.transferFrom() uses wrong error type
- [ ] **Fixed**
- **File:** `OptionFactory.sol:transferFrom()` (line 184)
- **Description:** `revert InvalidAddress()` for insufficient allowance. Should be `InsufficientAllowance()`.

### L-9: OptionFactory.optionsClaimFees() no validation of option addresses
- [ ] **Fixed**
- **File:** `OptionFactory.sol:optionsClaimFees()` (line 297-301)
- **Description:** Accepts arbitrary addresses without checking `options[addr]`. Calls `claimFees()` on unvalidated addresses.
- **Fix:** Add `require(options[options_[i]], "not a registered option");`

### L-10: OpHook.allPools unbounded array growth
- [ ] **Fixed**
- **File:** `OpHook.sol:initPool()` (line 381), `getPrices()` (line 336)
- **Description:** No mechanism to remove expired pools. `getPrices()` iterates entire array, will eventually hit gas limits.
- **Fix:** Add pool removal function or paginate `getPrices()`.

### L-11: OpHook.getPriceX64() precision loss
- [ ] **Fixed**
- **File:** `OpHook.sol:getPriceX64()` (line 294-298)
- **Description:** Shifts `sqrtPriceX96` right by 64 bits before squaring, losing lower 64 bits of precision. Can produce 0 for very small prices.
- **Fix:** Use `FullMath.mulDiv(uint256(sqrtPriceX96) * sqrtPriceX96, 1e18, 1 << 192)`.

### L-12: Self-transfer triggers auto-redeem
- [ ] **Fixed**
- **File:** `Option.sol:transfer()` (line 515-535)
- **Description:** `transfer(msg.sender, amount)` triggers auto-redeem on self if holding Redemption tokens. Unexpected position closure.
- **Fix:** Add `require(to != msg.sender)` or skip auto-redeem on self-transfer.

### L-13: Redemption._redeem() event emits wrong collateral amount
- [ ] **Fixed**
- **File:** `Redemption.sol:_redeem()` (line 314)
- **Description:** `emit Redeemed(..., amount)` emits the requested amount, not the actual `collateralToSend`. When partially fulfilled with consideration, the event overstates collateral.
- **Fix:** Emit `collateralToSend` instead of `amount`.

### L-14: Redemption.name() division by zero for puts on template
- [ ] **Fixed**
- **File:** `Redemption.sol:name()` (line 487)
- **Description:** `1e36 / strike` without `strike > 0` guard. Template has `strike = 0`. Option.sol has the guard but Redemption.sol does not.
- **Fix:** Add `strike > 0` guard like Option.sol.

### L-15: OptionPrice.blackScholesPrice() silent underlying=1 fallback
- [ ] **Fixed**
- **File:** `OptionPrice.sol:blackScholesPrice()` (line 75)
- **Description:** `if (underlying == 0) underlying = 1` produces meaningless prices instead of correct behavior (call=0, put=strike*exp(-rT)).
- **Fix:** Handle zero-underlying explicitly.

### L-16: OptionPrice.sol requires CLZ opcode (post-Pectra EVM)
- [ ] **Fixed**
- **File:** `OptionPrice.sol:log2()` (line 193-195)
- **Description:** Uses `clz` opcode from Solidity 0.8.33. Will fail at runtime on chains without this EVM feature.
- **Fix:** Document EVM version requirement. Consider fallback for broader compatibility.

---

## INFO

### I-1: Redemption transfers not blocked when locked
- **File:** `Redemption.sol`
- **Note:** Unlike Option (which overrides transfer with `notLocked`), Redemption uses default ERC20 transfers. Locked flag only prevents lifecycle operations, not token transfers. May be intentional (allow secondary market exit during emergency).

### I-2: setApprovalForAll() grants universal operator across all options
- **File:** `OptionFactory.sol:setApprovalForAll()` (line 221)
- **Note:** Operator approval covers ALL current and future Option contracts from this factory. No per-option scoping. Documented as intentional (ERC-1155 style).

### I-3: Cross-contract trust boundaries are correctly implemented
- **File:** All contracts
- **Note:** Redemption trusts Option (onlyOwner), Factory trusts registered Redemptions (mapping check), Option trusts its paired Redemption. Trust model is sound.

### I-4: Factory UUPS upgrade correctly restricted
- **File:** `OptionFactory.sol:_authorizeUpgrade()` (line 333)
- **Note:** Properly restricted with `onlyOwner`. Implementation has `_disableInitializers()`. Storage gap present.

### I-5: Clone storage layout is safe
- **File:** `Option.sol`, `Redemption.sol`
- **Note:** No storage collisions. ERC-7201 namespaced storage for OZ contracts. Independent clone storage.

### I-6: SafeERC20 used consistently
- **File:** All contracts
- **Note:** All external token transfers use `safeTransfer` / `safeTransferFrom`. No raw `.transfer()` calls found.

### I-7: Factory.transferFrom() bottleneck acts as global reentrancy barrier
- **File:** `OptionFactory.sol:transferFrom()`
- **Note:** All collateral/consideration movements through Factory are protected by `nonReentrant`. Only `_redeem()` direct transfers bypass this bottleneck.

### I-8: Max uint256 approvals handled correctly
- **File:** `OptionFactory.sol:transferFrom()` (line 185-186)
- **Note:** Infinite approvals skip decrement, matching ERC20 standard.

### I-9: Existing options survive factory upgrades
- **File:** Architecture-level
- **Note:** Clones reference the proxy address (unchanged during upgrade). Storage persists. Backward compatibility depends on the new implementation.

### I-10: Same-token collateral/consideration correctly blocked
- **File:** `OptionFactory.sol:createOption()` (line 132)
- **Note:** `if (collateral == consideration) revert InvalidTokens()`.

### I-11: OptionPoolVault not integrated with option system
- **File:** `OptionPoolVault.sol`
- **Note:** Minimal ERC4626 wrapper with empty hooks. No connection to OpHook or options. Appears to be a placeholder.

### I-12: Put option math is correct
- **File:** `Redemption.sol:toConsideration()`, `Option.sol:name()`
- **Note:** Strike inversion for display is cosmetic only. Core conversion math uses raw strike. Verified correct for standard put configurations.

---

## Audit Checklist by Contract

### Option.sol
- [ ] H-1: Fix post-expiration transfer revert (skip auto-redeem when expired)
- [ ] H-2: Remove auto-mint from transfer() (or make it a separate function)
- [ ] H-3: Make auto-redeem opt-in
- [ ] M-4: Override renounceOwnership() to prevent bricking
- [ ] L-5: Validate fee <= MAXFEE in init()
- [ ] L-7: Remove unchecked from fee calculation
- [ ] L-12: Handle self-transfer edge case

### Redemption.sol
- [ ] H-4: Restrict redeemConsideration() to self-only and/or post-expiration
- [ ] H-5: Implement pro-rata redemption distribution
- [ ] H-6: Add consAmount > 0 check in exercise; round up toConsideration
- [ ] H-7: Fix CEI violation in claimFees()
- [ ] H-8: Add _disableInitializers() to constructor
- [ ] M-1: Add nonReentrant to _redeemPair()
- [ ] M-3: Add fee-on-transfer check in exercise path
- [ ] M-11: Document rebasing/deflationary token limitations
- [ ] L-6: Validate option_ != address(0) in init()
- [ ] L-7: Remove unchecked from fee calculation
- [ ] L-13: Fix Redeemed event to emit actual collateral amount
- [ ] L-14: Add strike > 0 guard in name()

### OptionFactory.sol
- [ ] M-5: Add onlyOwner to claimFees() functions (or document as intentional)
- [ ] M-14: Add Approval event to approve()
- [ ] L-8: Fix error type in transferFrom() (InvalidAddress -> InsufficientAllowance)
- [ ] L-9: Validate option addresses in optionsClaimFees()

### OpHook.sol
- [ ] C-1: Add onlyOwner to initPool() + validate option provenance
- [ ] C-2: Use TWAP instead of spot price
- [ ] H-9: Add slippage protection (minAmountOut)
- [ ] H-12: Design collateral provisioning mechanism
- [ ] M-6: Expose pause/unpause + add whenNotPaused to _beforeSwap
- [ ] M-7: Implement Permit2 or remove references
- [ ] M-8: Verify _beforeAddLiquidity/_beforeDonate signatures
- [ ] M-9: Add reentrancy protection to _beforeSwap
- [ ] M-10: Add approval revocation mechanism
- [ ] M-13: Fix swapForOption to track actual minted amount
- [ ] L-10: Add pool removal / paginate getPrices()
- [ ] L-11: Fix precision loss in getPriceX64()

### OptionPoolVault.sol
- [ ] H-10: Add inflation attack protection (_decimalsOffset)

### OptionPrice.sol
- [ ] H-11: Add bounds to setVolatility() and setRiskFreeRate()
- [ ] M-12: Use saturating subtraction in blackScholesPrice()
- [ ] M-16: Document/extend normCdf lookup range
- [ ] L-3: Use OZ Ownable for ownership management
- [ ] L-15: Handle zero underlying explicitly
- [ ] L-16: Document CLZ opcode EVM requirement

### BatchMinter.sol
- [ ] Validate all options share same collateral (NatSpec mismatch)
- [ ] Consider max batch size limit

---

## Priority Remediation Order

**Immediate (before any deployment):**
1. C-1 + C-2: OpHook access control + TWAP
2. H-1: Post-expiration transfer revert
3. H-5: Pro-rata redemption
4. H-4: Restrict redeemConsideration
5. H-8: Template _disableInitializers

**High priority:**
6. H-2 + H-3: Auto-mint/auto-redeem in transfer
7. H-6: Zero-amount exercise
8. H-7: claimFees CEI
9. H-9 + H-12: OpHook slippage + collateral gap
10. H-10 + H-11: Vault inflation + pricing bounds

**Before mainnet:**
11. All MEDIUM findings
12. All LOW findings

---

*Generated by Claude Code -- 7 parallel audit agents across Access Control, Reentrancy/State, Math/Decimals, Economic/Game Theory, Proxy/Upgrades, External Integrations, and ERC20 Compliance/Edge Cases.*
