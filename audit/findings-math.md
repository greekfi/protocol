# Math / Encoding / Oracle Findings — Greek.fi Options Protocol

Scope: `foundry/contracts/{Option,Collateral,Factory,OptionUtils}.sol`, `foundry/contracts/oracles/{IPriceOracle,UniV3Oracle}.sol`, `foundry/contracts/libraries/{TickMath,CustomRevert}.sol`.

## Severity legend
- **Critical** — direct loss or invariant break with trivial trigger
- **High** — loss under plausible conditions or broken settlement for realistic assets
- **Medium** — bounded loss, wrong semantics at edges, or DoS on legal configurations
- **Low** — polish / hardening
- **Informational** — design note

## Summary

| ID | Severity | Title |
|----|----------|-------|
| C-1 | Critical | `redeemConsideration()` lets shorts drain the ITM reserve set aside for longs (settled modes) |
| C-2 | Critical | Pre-expiry `redeemConsideration()` settles shorts at strike regardless of spot; breaks waterfall in pair-redeem |
| H-1 | High→Info | UniV3Oracle window anchoring (downgraded after re-verification) |
| H-2 | High | `_tickToPriceWad` inverted branch uses `/` instead of `mulDiv`, truncates to 0 at extreme ticks; division-by-zero DoS |
| H-3 | High | Observation-buffer rollover permanently bricks `settle` (and therefore claim/redeem in settled mode) |
| H-4 | High | `_redeemProRata` mixes collateral-at-strike with real consideration balance; can revert after burn → loss of user funds |
| M-1 | Medium | Dust `_redeemConsideration` reverts after burn-simulation path; pair-redeem waterfall can trap 1-wei residuals |
| M-2 | Medium | `toNeededConsideration` ceiling at sub-wei prices — edge case on pathological strike/decimals combinations |
| M-3 | Medium | Put inversion `1e36 / strike` silently truncated by `uint96` cast in CreateParams; revert is generic Panic |
| M-4 | Medium | `strike * 10^consDecimals` overflows with `decimals() ≥ 48`; malicious ERC20 bricks redeem/exercise |
| M-5 | Medium | Stranded `optionReserveRemaining` after long-side never claims; short holders locked out permanently |
| M-6 | Medium | Settle-timing / hint race (flagged for upcoming Chainlink branch) |
| L-1 | Low | Chainlink oracle branch not yet implemented — pre-seed list of pitfalls to test |
| L-2 | Low | `uint160` cap on exercise conflicts with huge mints (UX brick, funds recoverable via pair-redeem) |
| L-3 | Low | `_claimForOption` has no `nonReentrant` — defense-in-depth note |
| L-4 | Low | Unreachable `len == 0` branch in `OptionUtils.strike2str` |
| L-5 | Low | `epoch2str` linear-in-years loop → ~35k iterations near `uint40.max`; callable via `name()` |
| I-1 | Info | Strike overflow envelope confirmed OK under `decimals ≤ 18` |
| I-2 | Info | `uint40` expiration fine; only concern is rendering (L-5) |
| I-3 | Info | `ArithmeticOverflow` error is misnamed — actually a uint160 cap check |

## Key findings (detail)

### C-1: `redeemConsideration()` can drain option-holder ITM reserve
**Location**: `Collateral.sol:433-450`
**Impact**: In settled American mode, `settle()` latches `optionReserveRemaining = O·(S-K)/S`, earmarked for longs' `claim()`. `redeemConsideration()` is gated only by `notLocked`/`nonReentrant`/`!isEuro` — no `notExpired`, no reserve accounting. Short holders can call it pre- or post-expiry and receive `toConsideration(amount)` out of the consideration balance, bypassing the reserve entirely. Post-settle, `_claimForOption` will `safeTransfer(holder, payout)` against a balance that no longer exists — the long's tokens are burned on line 422 *before* the transfer, so the revert destroys their option for zero payout.
**Scenario**: Settled WETH/USDC call, strike 3000. After some exercises the contract holds USDC. A short calls `redeemConsideration` pre-settle and walks with USDC at strike rate. Settle runs, reserves collateral that was never ring-fenced. Longs claim → revert → burned tokens, no payout.
**Fix**: Add `if (address(oracle) != address(0) && block.timestamp >= expirationDate) revert SettledOnly();` — or restrict the whole path to pre-expiry pair-redeem fallback only.

### C-2: Pre-expiry `redeemConsideration` lets shorts exit at strike regardless of spot
**Location**: `Collateral.sol:433-450`, waterfall at `Collateral.sol:299-301`
**Impact**: Pair-redeem waterfall (`_redeemPairInternal`) falls back to `_redeemConsideration(account, amount - balance)` when `collateral.balanceOf(this) < amount`. `amount - balance` is a *collateral-unit* shortfall, and `_redeemConsideration` multiplies by strike to get consideration owed. If a short already drained the USDC via `redeemConsideration`, a later legitimate long+short pair-redeemer has their burn succeed but their `safeTransfer` revert — funds lost on burn.
**Fix**: In the waterfall, hand out whatever consideration is actually available pro-rata, not the strike-scaled amount; or remove the waterfall and revert up-front.

### H-2: `_tickToPriceWad` put-path division-by-zero / truncation
**Location**: `UniV3Oracle.sol:192-196`
```solidity
consPerCollWad = (1e18 * 1e18) / token1PerToken0Wad;
```
**Impact**:
- At MAX_TICK (≈887,272), `token1PerToken0Wad` can be ~2e42; inverse `1e36/2e42 = 5e-7` → truncates to **0**. Oracle latches 0, option settles OTM regardless of true spot.
- At MIN_TICK (≈-887,272), `sqrtP ≈ 4.3e9`, `mulDiv(sqrtP, sqrtP, 2^96)` ≈ 0 after integer division → `token1PerToken0Wad = 0` → division-by-zero revert. `settle` reverts forever; option bricked.
- Comment claims "safe: sqrtP > 0 ensures token1PerToken0Wad > 0" — false at the MIN_TICK regime.
**Fix**: `if (token1PerToken0Wad == 0) revert; consPerCollWad = Math.mulDiv(1e18, 1e18, token1PerToken0Wad);` and clamp ticks away from extremes.

### H-3: Observation-buffer rollover permanently bricks settle
**Location**: `UniV3Oracle.sol:152`
**Impact**: `pool.observe([T+window, T])` reverts `OLD` once observations roll off the pool's ring buffer. For long-dated options on low-cardinality pools (default cardinality is small; pools need explicit `increaseObservationCardinalityNext`), observations for `[T-1800, T]` are overwritten within minutes to hours after expiry. After that, `settle` reverts forever → `redeem`, `claim`, `sweep` (in settled mode) all revert. Collateral locked permanently.
**Fix**: Oracle constructor calls `pool.increaseObservationCardinalityNext(sized_for_duration)`. Add a fallback settle path (Chainlink / last slot0 / owner-set emergency price) after a grace period.

### H-4: `_redeemProRata` mixes collateral-at-strike with real consideration balance
**Location**: `Collateral.sol:377-397`
**Impact**: `remainder = amount - collateralToSend` (collateral units); code pays `toConsideration(remainder)` (strike-scaled) rather than pro-rata from the actual consideration balance. Works if the contract accumulated *exactly* strike × exercised-units of consideration, but fails when:
- Dust rounding losses have shrunk the consideration balance below strike-implied amount.
- Someone transferred consideration in accidentally (first redeemer gets fully strike-paid, later redeemers find cupboard bare).
Because `_burn(account, amount)` at line 387 runs before transfers, a revert on `safeTransfer` destroys the user's position with zero payout.
**Scenario**: `totalSupply = 10e18`, contract has 5 WETH + 14999e6 USDC (1e3 short due to rounding elsewhere). Alice redeems 10e18 → `collateralToSend = 5e18`, `remainder = 5e18`, `consToSend = toConsideration(5e18) = 15000e6` > balance → revert, but burn already done.
**Fix**: Unify with `_redeemSettled` formulation: `consToSend = Math.mulDiv(amount, consBalance, ts)`. Never over-transfers; strike drops out of the post-expiry pro-rata path entirely.

### M-1: Dust redemptions revert after pair-redeem waterfall starts
**Location**: `Collateral.sol:446-447`, waterfall at `300`
**Impact**: `_redeemConsideration` reverts with `InvalidValue` when `toConsideration(collAmount) == 0`. Reachable from `_redeemPairInternal` waterfall with a 1-wei collateral shortfall. A matched long+short holder who is 1 wei short of full balance cannot close their position.
**Fix**: `if (consAmount > 0) safeTransfer(...)` instead of reverting.

### M-4: `strike * 10^consDecimals` overflows for tokens reporting `decimals ≥ 48`
**Location**: `Collateral.sol:556, 565, 574`
**Impact**: No bound on `decimals()` in `Collateral.init`. With `strike = uint96.max ≈ 7.92e28` and `decimals = 50`, `strike * 10^50 ≈ 7.92e78` overflows uint256 → Panic(0x11) on *every* exercise / redeem / redeemConsideration. Mint still works (doesn't call conversions), so attacker-proposed "evil token" with reported decimals=50 traps minted collateral permanently (only pair-redeem works before expiry, not post-expiry non-settled pro-rata).
**Fix**: In `init`: `if (cDec > 36 || clDec > 36) revert InvalidValue();`.

### M-5: Stranded `optionReserveRemaining` after longs never claim
**Location**: `Collateral.sol:463-477`, `_claimForOption`, `_redeemSettled`
**Impact**: Reserve = `O · (S-K)/S` latched at settle. Only decreases when longs actually claim. Dust holders gas-uneconomic to claim → reserve stays nonzero forever → `availableColl = collBalance - reserve` is permanently reduced → short redeemers never recover full share.
**Fix**: `sweepReserve()` callable after `expirationDate + grace` that zeros out and releases the remainder to shorts.

### M-3: Put encoding & `uint96` silent overflow
**Location**: `Factory.sol` CreateParams struct (`uint96 strike`), put inversion logic
**Impact**: User encodes `strike = 1e36 / humanPutStrike` off-chain and passes as `uint96`. Human strikes below ~1.26e-11 (in 18-dec) overflow uint96 at cast → generic `Panic(0x11)`. Benign in practice but should be a dedicated error with validation.
**Fix**: Either take `humanPutStrike` and encode in the factory with explicit range check, or document and add a StrikeOutOfRange custom error.

### M-6: Settle-timing hint race (forward-looking, Chainlink branch)
**Location**: `Factory.sol:237-246` (Chainlink planned)
**Impact**: When Chainlink settle lands with `hint = abi.encode(roundId)`, without enforcing "earliest post-expiry round", an early-round hint can latch a pre-expiry price. Caller-controlled settlement timing.
**Fix**: Require `updatedAt >= EXPIRATION_TS` and `prevRound.updatedAt < EXPIRATION_TS`; also require `answeredIn >= roundId` (not stale), `ans > 0` (not zero/negative, which otherwise wraps when cast to uint).

### L-1: Chainlink branch not implemented — known-pitfall list for when it ships
1. Negative `int256` answer cast to `uint256 * 1e10` wraps → always ITM.
2. No `updatedAt + heartbeat < block.timestamp` staleness check.
3. `answeredIn < roundId` = round answered in a later round = stale.
4. Hardcoded `*1e10` assumes 8-dec feed; some L2 feeds are 18-dec.
5. Cross-asset paths (ETH/USD ÷ USDC/USD): one stale leg poisons the derived price.

### L-2: `uint160` cap collides with decimal-normalised consideration
**Location**: `Collateral.sol:264, 331`
**Impact**: Mint caps `amount` at uint160.max (~1.46e48). Exercise caps `consAmount` at uint160.max, computed from `toNeededConsideration`. For a WETH/USDC call at K=3000e18, a valid mint of 1e45 WETH would require `3e51` USDC-wei on exercise → overflows uint160, reverts. Funds recoverable via pair-redeem, but UX is broken.
**Fix**: Also clamp `amount` at mint so `toNeededConsideration(amount)` fits in uint160; or allow exercise in chunks.

### L-5: `epoch2str` O(years) loop → gas DoS on `name()`/`symbol()`
**Location**: `OptionUtils.sol:167-179`
**Impact**: For `expirationDate` near `uint40.max` (year ~36812), ~35k iterations. Callable via `name()`, `symbol()`, `details()`. On-chain metadata aggregators iterating options can be gas-gridded by a single pathological option.
**Fix**: Replace with O(1) Howard Hinnant civil-from-days formula.

### Things checked and OK
- `Math.mulDiv` with `Rounding.Ceil` used correctly; no silent truncation.
- Modifier logic: `block.timestamp < expirationDate` vs `>=` is consistent: `expirationDate` is the first post-expiry second.
- Fee-on-transfer detection is present on `mint` and `exercise`.
- Clone + initializer + `_disableInitializers` on templates prevent takeover.
- `approve`/`transferFrom` factory allowance correctly handles `type(uint256).max` sentinel.
- `autoMintRedeem` opt-in on *both* sender and receiver — confirmed in `_settledTransfer`.
- `renounceOwnership` disabled on Option — intentional anti-rug.
- UniV3Oracle window anchoring to `EXPIRATION_TS`: on re-verification, `secondsAgos = [delta+window, delta]` is correctly relative to `block.timestamp`, yielding `[T-window, T]` — H-1 retracted into Informational.

### Priority remediation order
1. Gate / remove `redeemConsideration` (C-1, C-2).
2. Rewrite `_redeemProRata` consideration leg as pure pro-rata (H-4).
3. Harden UniV3Oracle: mulDiv on inverse, cardinality bump in constructor, fallback path (H-2, H-3).
4. Bound `decimals()` in `Collateral.init` (M-4).
5. Add reserve grace-period sweep (M-5).
6. When Chainlink oracle lands, implement full validation from L-1 / M-6.
