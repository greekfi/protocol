# Core / Invariants / Access Control Findings

Scope: `foundry/contracts/{Factory,Option,Collateral,OptionUtils}.sol`, `interfaces/*`, and `oracles/UniV3Oracle.sol` as a support contract for settled modes.

## Severity legend
- **Critical** — funds at imminent risk, protocol-breaking
- **High** — significant fund/function risk with a clear path
- **Medium** — conditional exploit, economic loss possible
- **Low** — hardening / best practice
- **Informational** — no direct impact, but worth documenting

---

## Findings

### C-1: Settled options can permanently lock funds if `settle` isn't called before the Uniswap v3 observation ring-buffer rolls off expiration
**Severity**: Critical
**Location**:
- `foundry/contracts/oracles/UniV3Oracle.sol:131-166` — `settle(bytes)`
- `foundry/contracts/Collateral.sol:463-477` — `_settle`
- `foundry/contracts/Collateral.sol:366-373` — post-expiry `redeem` requires `_settle` first in settled mode
- `foundry/contracts/Collateral.sol:485-499` — `_claimForOption` requires `_settle` first

**Impact**: If `settle` is not called within the pool's observation buffer window after expiration, every post-expiry redemption path (long-side `claim`, `claimFor`; short-side `redeem`, `sweep`) is permanently bricked because all of them unconditionally call `_settle`, which calls `POOL.observe([expiration - twapWindow, expiration])`. Once the observation for `expiration - twapWindow` has been overwritten in the pool's ring buffer, `observe()` reverts with `OLD`. There is no escape hatch: no fallback oracle, no admin override, no "assume OTM" path, no timeout-triggered default settlement. All collateral and consideration tokens become permanently unreachable.

**Scenario / PoC**:
1. Create a European WETH/USDC option with `oracleSource = a low-activity Uniswap v3 pool`, `twapWindow = 1800`.
2. Option expires at time T. Users mint a total of 100 WETH of long + short.
3. The pool has `observationCardinality = 50`. During the month between creation and expiry there are ~1000 swaps that each roll the observation slot. By `T + ~30 min`, the `T - 1800` observation has been overwritten.
4. Alice calls `claim`: `_settle` → `oracle.settle("")` → `POOL.observe([1800+ago, ago])` → reverts with `OLD`.
5. Same for Bob calling short-side `redeem`. Same for `claimFor`, `sweep(single)`, `sweep([])`.
6. All 100 WETH + any collected USDC are stuck in `Collateral` forever.

Amplified by: pools with low `observationCardinality` (default 1 unless explicitly grown), long `twapWindow`, low-liquidity pairs.

**Root cause**: `_settle` has no recovery path. No `increaseObservationCardinalityNext` call at oracle construction.

**Remediation**:
- At `UniV3Oracle` construction, call `POOL.increaseObservationCardinalityNext(required)` sized for `twapWindow + buffer_margin`.
- Provide a fallback / escape: if `settle` has failed for N days past expiration, allow an emergency unwind that distributes everything pro-rata to short-side holders.
- Alternatively, fall back to `_redeemProRata` semantics on settlement failure.

---

### C-2: `Collateral.redeem(account, amount)` and `sweep(address)` are fully public — any caller can force another user's post-expiry redemption
**Severity**: Critical (fund-draining against certain tokens) / High (griefing against benign tokens)
**Location**: `foundry/contracts/Collateral.sol:366-373` (`redeem(address,uint256)`), `:506-515` (`sweep(address)`), `:520-533` (`sweep(address[])`)

**Impact**: `redeem(account, amount)` has only `expired notLocked nonReentrant` — no `msg.sender == account`, approval, or operator check. Any caller can burn any holder's short-side balance post-expiry. The NatSpec calls this a "keeper sweep", but it's unbounded third-party authority.

**Scenario / PoC — forced unwanted redemption**:
Bob is a short-side holder who wants to defer redemption for tax timing. Anyone can call `sweep(bob)` the instant the option expires, forcing realization.

**Scenario / PoC — DOS against a blacklist-aware consideration token**:
Consideration is USDT. If an account is USDT-blacklisted at redemption time, the `safeTransfer` reverts. Combined with M-2, a griefer can strategically call `redeem(victim, huge)` in sandwiches that affect ordering and leave honest redeemers facing `InsufficientConsideration`.

**Root cause**: `redeem(address,uint256)` and both `sweep` overloads lack access control.

**Remediation**:
- Require `msg.sender == account` OR factory-approved operator OR a per-account opt-in sweep flag.
- OR gate keeper sweeps behind a grace period (`expiration + GRACE`) after which 3rd-party sweeps are allowed.

---

### H-1: Cross-option / read-only re-entrancy via hook-enabled collateral tokens during pair-redeem and auto-redeem
**Severity**: High
**Location**:
- `foundry/contracts/Option.sol:291-307` — `_settledTransfer`
- `foundry/contracts/Collateral.sol:283-307` — `_redeemPair`, `_redeemPairInternal`
- `foundry/contracts/Collateral.sol:439-450` — `_redeemConsideration`

**Impact**: `ReentrancyGuardTransient` is per-contract. Each Option/Collateral clone has its own guard. When `Option.transfer` runs with auto-redeem-on-receive, control reaches `collateral.safeTransfer(to, collateralToSend)` AFTER `_burn(account, collateralToSend)`. If the collateral is a hook-enabled token (ERC777, ERC1363, or a custom pull-callback token), the receive hook runs while Collateral state is mid-update. The hook can:
1. Call the same Option/Collateral — blocked by nonReentrant.
2. Call **any other option pair** this factory created — NOT blocked; each clone has its own guard.
3. Call `factory.approveOperator(attacker, true)` — state change usable post-callback.

**Concrete read-only-reentrancy exploit**: Between `_burn` at Collateral.sol:297 and `safeTransfer` at :304, `Collateral.totalSupply` has decreased but `collateral.balanceOf(this)` hasn't. Any external integrator (market maker, oracle consumer, vault NAV calculator) reading `collateral.balanceOf(coll) / coll.totalSupply()` sees an inflated ratio. An attacker routing a quote request through that integrator during the hook gets mispriced.

**Root cause**: State updates and external calls interleave without cross-contract locking; no filter on hook-enabled tokens.

**Remediation**:
- Factory-time ERC165 sniffing to reject ERC777/ERC1363 collateral/consideration tokens.
- Document the read-only reentrancy surface for integrators.

---

### H-2: Rebasing (stETH-style) collateral bricks exercise via `sufficientCollateral` modifier and breaks the `available_collateral == total_option_supply` invariant
**Severity**: High (protocol-breaking for any rebasing token)
**Location**: `foundry/contracts/Collateral.sol:187-190` (modifier), `:317-338` (`exercise`)

**Impact**: `exercise` has `sufficientCollateral(amount)` requiring `collateral.balanceOf(this) >= amount`. FOT detection in `mint` (line 269) catches first-mint deflation, but does NOT catch negative rebases that happen AFTER mint. If 100 stETH is in the contract and a Lido slashing event drops it to 99.5, the 100th exerciser hits `InsufficientCollateral` and cannot exercise.

**Scenario / PoC**:
1. 100 stETH collateral, 100 options minted.
2. Slashing event → contract has 99.5 stETH.
3. Alice tries exercise(100) → `sufficientCollateral(100)` fails (99.5 < 100). Revert.
4. She exercises 99 successfully. Contract now has 0.5 stETH left.
5. Bob tries exercise(1) → fails (0.5 < 1). Bob is stuck with 1 Option he cannot exercise.

The same issue breaks post-expiry settled redemption: `availableColl = collBal - reserve`; rebasing collateral drops collBal below reserve, zeroing `availableColl` for short-side redeemers.

**Root cause**: The `balance ≥ amount` modifier treats the accounting as exact, but rebasing tokens violate it.

**Remediation**:
- Document that rebasing tokens are unsupported; add ERC165 / heuristic detection at `createOption` time.
- OR adopt "cap amount at actual balance" semantics for exercise and adjust the Option layer to report actual delivered amount.
- Add a Factory-level allowlist or enforce reject via a shares-based adapter pattern.

---

### H-3: Factory `approveOperator` is GLOBAL across every option (past AND future) — a one-time grant cannot be scoped
**Severity**: High
**Location**: `foundry/contracts/Factory.sol:303-308` — `approveOperator`, `foundry/contracts/Option.sol:318-333` — `transferFrom` honors the factory flag

**Impact**: `factory.approveOperator(router, true)` gives `router` blanket authority over **every** option the factory has ever created AND **every option it will create in the future**. Unlike ERC-1155 (bounded to a single collection), here the "collection" is all options pairs the factory mints.

**Scenario / PoC**:
1. Alice approves Bebop router as operator to skip per-option approvals (intended UX).
2. Six months later, Alice mints a new option in a different market.
3. If Bebop is ever exploited or its key rotates to malicious control, ALL Option tokens Alice holds — including the brand new one — are drainable. No way to scope the original grant to a single market.

**Root cause**: ERC-1155-style global approval without scoping.

**Remediation**:
- Add per-option operator approval: `approveOperatorFor(option, operator, approved)`.
- OR add expiry: `approveOperator(operator, approved, validUntil)`.
- Emit warning / require user ACK before granting global operator.

---

### H-4: `Factory.renounceOwnership` is inherited unchanged, permanently bricking the blocklist if called
**Severity**: High (irreversible if ever triggered)
**Location**: `foundry/contracts/Factory.sol:77` (inherits Ownable, no override)

**Impact**: `Option.renounceOwnership` is explicitly disabled (`Option.sol:493-495`), but `Factory.renounceOwnership` is not. If ever called, `blockToken` / `unblockToken` become uncallable forever. When a token later becomes problematic (FOT activated by upgrade, rebasing adapter added, circle-freeze of USDC, USDT blacklist, etc.), nothing can be done — new options against it still deploy successfully.

**Root cause**: Standard `Ownable.renounceOwnership` inherited without override.

**Remediation**: Override `renounceOwnership` in Factory to revert, mirroring `Option`. Switch to `Ownable2Step` for the ownership transfer.

---

### H-5: `_deployOracle` accepts ANY contract whose `expiration()` returns `p.expirationDate` as a trusted oracle — enables attacker-controlled settlement prices
**Severity**: High (if option creators are adversarial; relevant for any open-listing flow)
**Location**: `foundry/contracts/Factory.sol:237-246`

**Impact**: `try IPriceOracle(p.oracleSource).expiration() returns (uint256 exp) { if (exp == p.expirationDate) return p.oracleSource; }` — no further validation. A contract that returns the expected expiration and a malicious `settle(bytes)` is accepted as trusted oracle forever. The factory also has no code-hash allowlist.

**Scenario / PoC**:
1. Attacker deploys `FakeOracle { function expiration() returns (uint256) { return TARGET_EXPIRY; } function settle(bytes) returns (uint256) { return type(uint256).max; } }`.
2. Attacker calls `factory.createOption({..., oracleSource: FakeOracle, isEuro: true})`.
3. A frontend displays this as "European WETH/USDC 3000 call" without verifying oracle provenance.
4. Victim mints both sides, attacker buys option.
5. Post-expiry `_settle` sets `S = MAX`, so `reserve = O * (MAX-K)/MAX ≈ O`. Essentially the entire collateral pool becomes the option-holder reserve.
6. Attacker claims → drains almost all collateral. Short-side gets nothing.

**Root cause**: No oracle allowlist / code-hash pinning / deployed-by-factory-only restriction.

**Remediation**:
- Factory-owner-controlled oracle registry.
- Require oracles to be deployed *by* the factory (reject pre-deployed oracle reuse; always wrap pool sources as UniV3Oracle).
- Sanity-bound settled price at `[strike * 0.01, strike * 100]` or similar.

---

### H-6: Planned Chainlink branch unsafe cast & missing staleness checks in CLAUDE.md-documented pattern
**Severity**: High (latent; triggers when Chainlink oracle is implemented)
**Location**: Referenced in CLAUDE.md and the reserved Chainlink branch of `_deployOracle`; not yet implemented

**Impact**: The doc's pattern `uint256 spot = uint256(chainlinkPrice) * 1e10;` is unsafe — if `chainlinkPrice < 0` (Chainlink returns int256), the cast wraps to ~2^256, multiplied by 1e10 wraps further. Settlement uses nonsense price. Doc also omits `updatedAt` staleness check, `answeredInRound >= roundId` round-completeness, and phase-ID awareness.

**Remediation**: When implemented: `require(price > 0); require(block.timestamp - updatedAt <= MAX_STALE); require(answeredInRound >= roundId);`. Use `SafeCast.toUint256`.

---

### M-1: `_redeemPairInternal` silently switches from pure-collateral to collateral+consideration-at-strike-rate when collateral pool is partially exercised — no slippage control
**Severity**: Medium
**Location**: `foundry/contracts/Collateral.sol:288-307`

**Impact**: `Option.redeem(amount)` → `coll._redeemPair(account, amount)` → `_redeemPairInternal` waterfall:
```
uint256 balance = collateral.balanceOf(this);
uint256 collateralToSend = amount <= balance ? amount : balance;
_burn(account, collateralToSend);
if (balance < amount) _redeemConsideration(account, amount - balance);   // strike-rate cons payout
if (collateralToSend > 0) collateral.safeTransfer(account, collateralToSend);
```
Collateral math is consistent (net burn = amount) but the PAYOUT the user receives silently changes: when the pool has been partially exercised, the user gets `balance` WETH + `(amount - balance)` worth of USDC at STRIKE rate, instead of pure WETH. If spot has moved against the strike, this is a material loss.

**Scenario / PoC**:
1. 100 WETH/USDC call, strike 3000. Alice mints 100 (holds 100 Opt + 100 Coll). Sells 50 Opt to Bob.
2. Bob exercises 50 — pays 150k USDC, gets 50 WETH. Contract has 50 WETH + 150k USDC.
3. Alice re-buys 50 Opt and calls `redeem(100)`.
4. Gets 50 WETH + 150k USDC. If spot is now 3500 USDC/WETH (ITM direction), 150k USDC = 42.86 WETH → Alice got 92.86 WETH-equivalent instead of 100. Loss.

**Root cause**: No slippage / min-out on `Option.redeem`; no authorization for the consideration-substitution.

**Remediation**: Add `Option.redeem(amount, minCollateralOut)` slippage param, OR revert outright when `balance < amount` and force users to wait for post-expiry pro-rata.

---

### M-2: `_redeemProRata` pays consideration at strike-rate (not pro-rata) — if accounting drifts even slightly, later redeemers revert with `InsufficientConsideration`
**Severity**: Medium
**Location**: `foundry/contracts/Collateral.sol:377-397`

**Impact**:
```
collateralToSend = mulDiv(amount, collateralBalance, ts);
remainder = amount - collateralToSend;
consToSend = toConsideration(remainder);  // strike-rate, not pro-rata!
consideration.safeTransfer(account, consToSend);
```
In a perfectly clean protocol, `toConsideration(remainder)` always fits in `consBalance`. But any drift (FOT hidden in a variant, token admin freeze, donation-tracking tokens, yield-bearing adapters) and later redeemers revert. Unlike the collateral side (pro-rata of balance), the consideration payout is strike-rate fixed.

**Remediation**: Fall back to pro-rata consideration payout when strike-rate math exceeds balance: `consToSend = min(toConsideration(remainder), mulDiv(remainder, consBalance, remainderSupply))`.

---

### M-3: Stale reserve dust permanently stuck when option holders fail to claim — no recycle path
**Severity**: Medium
**Location**: `foundry/contracts/Collateral.sol:463-477` (set reserve), `:485-499` (decrement on claim), `:401-418` (never recycled)

**Impact**: Reserve = `Option.totalSupply_at_settle * (S-K)/S`. Decremented only via `_claimForOption`. If any option holder never claims (lost keys, abandoned position), their reserve share sits in the contract forever. Short-side holders cannot access it.

**Remediation**: Add `releaseStaleReserve()` callable after `expiration + STALE_WINDOW` (e.g. 1 year) that returns unclaimed reserve to `availableColl`. Alternatively, when `Option.totalSupply()` reaches zero post-expiry (all claims burned supply), auto-release.

---

### M-4: Auto-mint in `_settledTransfer` lets a malicious receiver (or a compromised operator) drain the sender's full factory collateral allowance via a single transfer
**Severity**: Medium
**Location**: `foundry/contracts/Option.sol:291-307`

**Impact**: If sender has `autoMintRedeem` enabled AND holds less Option than the transfer `amount`, `_settledTransfer` pulls `deficit` collateral from sender via `mint_` → `coll.mint` → `_factory.transferFrom`. A function labeled "transfer" has the side effect of minting new collateral positions, consuming factory allowances. Combined with operator approvals (H-3), this is particularly dangerous.

**Scenario / PoC**:
1. Alice sets `factory.approve(WETH, 100e18)` as a long-lived allowance.
2. Alice enables `autoMintRedeem`. Holds 0 Option.
3. Any operator or ERC20-approved address calls `option.transferFrom(alice, evil, 100e18)`.
4. `_settledTransfer`: balance 0 < 100e18 → auto-mint pulls 100 WETH from alice → transfers 100 Option to evil.
5. Alice lost 100 WETH via what she perceived as a "transfer".

**Root cause**: Auto-mint combines three distinct authorities into one code path.

**Remediation**: Cap auto-mint per transfer (e.g. `deficit <= autoMintCap[from]`); require both sender and caller to have `autoMintRedeem` enabled; or require an explicit `consent` signature for auto-mints above a threshold.

---

### M-5: Factory `_allowances` is uint256 but `transferFrom` takes uint160 — mismatched typing obscures allowance accounting
**Severity**: Medium (hygiene / latent auditability)
**Location**: `foundry/contracts/Factory.sol:260-273`

**Impact**: `approve` sets uint256; `transferFrom` accepts uint160. `amount <= uint160.max` per call (no practical issue for typical decimals). But allowance = `type(uint256).max` bypasses decrement, while large-but-finite allowances do decrement. The mixed typing can confuse integrators who expect Permit2-style uint160 allowances.

**Remediation**: Pick one: either store `_allowances` as uint160 (reject approve > uint160.max) OR accept uint256 in `transferFrom`. Unify.

---

### L-1: `Collateral.renounceOwnership` not overridden — a bug in Option could brick Collateral
**Location**: `foundry/contracts/Collateral.sol` (inherits Ownable, no override)

**Impact**: Collateral's owner is the paired Option. Today Option never calls `coll.renounceOwnership`, but a future refactor / bug could. Would brick `onlyOwner` paths (mint, exercise, `_redeemPair`, `_claimForOption`).

**Remediation**: Override `renounceOwnership` and `transferOwnership` in Collateral to revert or gate behind the factory.

---

### L-2: `_redeemPairInternal` emits a single `Redeemed` event for collateral-only, but may also internally emit one for consideration — pair redemption is fragmented across two events
**Location**: `foundry/contracts/Collateral.sol:306`

### L-3: `Option.claim` / `claimFor` hardcode empty settle hint — blocks future Chainlink oracles that need a `roundId`
**Location**: `foundry/contracts/Option.sol:421, 435`

### L-4: `sweep(address[])` has no length cap — unlimited gas griefing
**Location**: `foundry/contracts/Collateral.sol:520-533`

### L-5: `_redeemPair` named with leading underscore but is `public` — violates conventional "internal" signaling
**Location**: `foundry/contracts/Collateral.sol:283`

### L-6: Blocklist applies to tokens but not to `oracleSource`
**Location**: `foundry/contracts/Factory.sol:157-159`

### L-7: `createOption` allows unlimited duplicate options with identical params — spam / indexer bloat
**Location**: `foundry/contracts/Factory.sol:157-191`

### I-1: `_deployOracle` expiration-match comparison is minimal — covered by H-5
### I-2: `createOptions` batch has no outer nonReentrant — each inner `createOption` has one; safe but worth noting
### I-3: Templates' `_disableInitializers` runs in constructor — rogue EIP-1167 clones pointing at Option template can be initialized by anyone but cannot drain funds because Factory's `colls[]` / `options[]` gating prevents them from pulling user tokens. Document this trust boundary.
### I-4: `Option.mint(uint256)` (single-arg) lacks nonReentrant; delegates to two-arg which has it. Safe but readers may miss.
### I-5: `Collateral._claimForOption` lacks local `expired` modifier; depends on caller (`Option.claim`) checking. Defense-in-depth suggestion.
### I-6: `approveOperator` self-approval check reverts with `InvalidAddress` — misleading error name.
### I-7: Factory does not call `pool.increaseObservationCardinalityNext` on the Uniswap pool at oracle deployment — tied to C-1.

---

## Invariant summary

| Invariant | Holds? | Notes |
|-----------|--------|-------|
| `available_collateral >= Option.totalSupply` (pre-expiry) | Yes if no rebasing/FOT | Breaks for rebasing tokens (H-2) |
| `Option.totalSupply <= Collateral.totalSupply` | Yes | Pair-redeem burns both; exercise burns only Option |
| Reserve = `O_settle * (S-K)/S` | Yes at settle | Stale reserve if holders don't claim (M-3) |
| `_redeemSettled` availableColl >= 0 | Yes | Guarded |
| `sum(claim payouts) <= reserve` | Yes | Cap in `_claimForOption` |
| `_redeemProRata` exhausts balances cleanly | Approximate | Strike-rate consideration can revert (M-2) |
| Oracle settles exactly once | Yes | UniV3Oracle guards with `settled` flag |
| Post-expiry no new Option supply | Yes | `mint`/`transfer` have `notExpired` |
| Factory ownership recoverable | NO if renounced (H-4) |   |

---

## Handoffs

Concerns that cross into non-core code — for the integration / market-maker auditor:

1. **YieldVault.sol** — `execute(target, calldata)` is an arbitrary-call pattern. Combined with H-3 (global operator approval), operator compromise is particularly dangerous. Verify allowlist, `setupFactoryApproval` minimality, `addOption` validation.

2. **Bebop / RFQ integration** — signed quotes must bind `(option, expiry, strike, chainId, quoteId, expires)` to prevent cross-option or cross-chain replay.

3. **Frontend trust boundary** — Must verify `factory.options[clone] == true` before treating an address as an Option. I-3 relies on this.

4. **Rebasing-token integration path** — H-2 becomes Critical if stETH-like collateral is supported. Audit token-adapter code.

5. **Chainlink oracle branch** — H-6 + L-3 must both be addressed at implementation.

6. **Frontend approval UX** — granting `factory.approveOperator(router, true)` (H-3) should have an explicit scary warning. No ERC20 mental-model parallel.

7. **Universal Router / Permit2 integration** — If added as a second approval path, ensure deadline + nonce replay protection match Permit2 semantics; current `transferFrom(uint160)` mimics Permit2 types but has no replay protection of its own.
