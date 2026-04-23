# Token / Integration / Vault Findings — Greek.fi Protocol

**Scope**: `Factory.sol`, `Option.sol`, `Collateral.sol`, `YieldVault.sol`, plus Permit2/EIP-712/ERC-7540/JamSettlement interfaces.

**Severity legend**: Critical / High / Medium / Low / Informational

---

## Critical

### C-1 — YieldVault `execute(target, data)` has no target allowlist
**Location**: `YieldVault.sol:334-340` (`execute`), `:421-423` (`approveToken`), `:405-408` (`setupFactoryApproval`)
**Impact**: `execute` forwards arbitrary calldata from the vault as `msg.sender` with zero target/selector restrictions. Combined with `approveToken`, the entire pool is drainable on operator/owner key compromise.
**Scenario**:
1. Attacker with operator access calls `vault.execute(WETH, abi.encodeCall(IERC20.transfer, (attacker, 1000e18)))` — idle WETH gone.
2. `vault.approveToken(anyERC20, attacker, max)` then drain via standard `transferFrom`.
3. `vault.execute(FACTORY, abi.encodeCall(Factory.approve, (WETH, max)))` then a pre-existing Collateral clone can pull via `Factory.transferFrom`.
4. `isValidSignature` allows operator to sign arbitrary Bebop order flow on the vault's behalf.
**Root cause**: Generic proxy with no allowlist, selector filter, rate limit, or role split.
**Remediation**: Restrict `target ∈ {BEBOP_SETTLEMENT, BEBOP_BLEND}`, selector allowlist (`swapSingle.selector`). Separate "trading operator" from "admin operator". Add timelock on `setOperator`.

### C-2 — `setupFactoryApproval` exposes vault to every Collateral clone the factory has ever created
**Location**: `YieldVault.sol:405-408`; `Factory.sol:260-273`
**Impact**: `setupFactoryApproval` calls `IERC20(asset()).forceApprove(factory, max)` + `factory.approve(asset(), max)`. Factory's `transferFrom` is gated only by `colls[msg.sender]` — i.e., the caller is **any** Collateral clone the factory has ever deployed, not just the vault's options.
**Scenario**:
1. Vault runs `setupFactoryApproval()` for Bebop flow.
2. Attacker deploys a fresh Option via `factory.createOption(WETH, X, ...)` — their Collateral clone is now registered in `colls[]`.
3. Attacker triggers their clone to call `factory.transferFrom(vault, attacker, vault_WETH_balance, WETH)` — succeeds because `_allowances[WETH][vault] == max` and the caller is a registered clone.
4. Vault drained.
**Root cause**: Factory allowance registry is global across all clones, not scoped to participating pairs; `to` in `Factory.transferFrom` is caller-chosen.
**Remediation**: Do not grant `max` allowance (set per-trade), OR pin `to = msg.sender` in `Factory.transferFrom`, OR scope `_allowances` to `(token, owner, option)` triplets.

### C-3 — `addOption(option, spender)` accepts arbitrary address + infinite approve
**Location**: `YieldVault.sol:430-435`
**Impact**: Owner-only but zero validation: `option` is not checked against `factory.options[]`, and `option != asset()` is not enforced. A mis-directed `addOption(WETH, attacker)` grants infinite WETH allowance to `attacker`.
**Scenario**: Operator is social-engineered (or a compromised admin UI) into `addOption(WETH, attacker)`. `forceApprove(WETH, attacker, max)` → attacker drains WETH via `transferFrom`.
**Root cause**: `option` typed as `address`, not `IOption`; no validation.
**Remediation**: `require(factory.options(option))`; reject `option == asset()`; cap approval.

---

## High

### H-1 — Factory `_allowances` is global; third-party `Option.mint(account, ...)` drains user approvals
**Location**: `Factory.sol:93, 260-273`; `Option.sol:276-278`
**Impact**: `_allowances[token][owner]` is a single global slot consumed by every Collateral clone. `Option.mint(address account, uint256 amount)` is `public` and does NOT check `msg.sender == account` or `approvedOperator(account, msg.sender)`. So anyone can mint an option *for* a victim and pull from the victim's factory allowance.
**Scenario**: Alice `factory.approve(WETH, 1e18)` intending to mint a WETH/USDC call. Bob creates a junk pair (WETH/X), calls `Option.mint(alice, 1e18)`. Collateral's `mint` calls `_factory.transferFrom(alice, coll_of_bob, 1e18, WETH)`; succeeds. Alice now owns short+long of Bob's junk option.
**Root cause**: Conflation of "single UX approval" with "scoped approval".
**Remediation**: Require `msg.sender == account || factory.approvedOperator(account, msg.sender)` in `Option.mint(account, amount)`. OR scope allowances per-option.

### H-2 — `Factory.transferFrom` accepts caller-supplied `to`
**Location**: `Factory.sol:260-273`
**Impact**: `to` is trusted to be the calling Collateral's address but never validated. Currently mitigated because Collateral clones are immutable EIP-1167 proxies and the template always passes `to = address(this)`, but any future Collateral variant that passes a different `to` would silently redirect user funds.
**Remediation**: Remove `to` param and pin `to = msg.sender` inside `Factory.transferFrom`.

### H-3 — Rebasing collateral (stETH, AMPL) breaks `available_collateral == total_option_supply` invariant
**Location**: `Collateral.sol:266-273, 377-397`
**Impact**: Mint-time balance-diff check passes for stETH (no fee on single transfer), but stETH rebases up over time → pro-rata `_redeemProRata` over-pays early redeemers. AMPL negative rebase → contract's balance drops below totalSupply; late redeemers revert when the waterfall tries `_redeemConsideration` with empty consideration.
**Scenario** (stETH): 100 stETH minted → one week later contract holds 100.4 stETH but totalSupply still 100e18 → first redeemer gets 1.004× their share.
**Scenario** (AMPL): 100 AMPL minted → negative rebase halves to 50 AMPL → first half redeems OK, second half reverts.
**Remediation**: Explicit blocklist for rebasing tokens; require share-wrapped variants (wstETH). Cap pro-rata payouts at `amount` not at rebased surplus.

### H-4 — USDC/USDT blacklist or pause of the Collateral contract bricks redeem/exercise
**Location**: `Collateral.sol:304, 394, 416, 448, 495`
**Impact**: If `address(collateralContract)` gets OFAC-blacklisted on USDC (has happened for Tornado-linked addresses) or USDC is paused, every `safeTransfer`/`safeTransferFrom` reverts. Exercise bricks, redeem bricks, sweep bricks. No recovery path.
**Scenario**: WETH/USDC call option, Collateral contract hits OFAC list → USDC cannot flow in (exercise fails) or out (redeem fails); entire pair frozen permanently.
**Remediation**: Add admin-controlled escape hatch that re-routes payouts to a replacement token/address. At minimum document pause risk.

### H-5 — Dual-layer approval + USDT's "zero-first" quirk
**Location**: Factory at `:289-293` + user-layer ERC20 approval
**Impact**: Users must approve twice: `USDT.approve(factory, x)` AND `factory.approve(USDT, x)`. USDT's classic rule requires zero-first when raising a nonzero allowance. Any UX that tops up without zeroing causes silent failure at the token layer while factory allowance succeeds.
**Remediation**: Provide a factory helper that calls `forceApprove` at the ERC20 layer on behalf of users via permit.

### H-6 — ERC-777 / ERC-1363 transfer hooks enable cross-option reentrancy via shared allowance registry
**Location**: `Option.sol:291-307`; `Factory.sol:260-273`
**Impact**: `_settledTransfer` calls `mint_ → coll.mint → factory.transferFrom → token.safeTransferFrom(sender, ...)` BEFORE the outer `_transfer`. Token hook fires on sender → sender's contract can re-enter a *different* Option's `mint`/`exercise` (different `nonReentrant` slot) and pull extra tokens from the user's shared factory allowance.
**Scenario**: ERC-777 collateral; user Alice with auto-mint enabled and a `factory.approve(token, maxAllowance)`. Alice calls `option1.transfer(recipient, amount)`. During `safeTransferFrom`, Alice's `tokensToSend` hook fires, calls `option2.mint(alice, evilAmount)` — pulls again from the same allowance.
**Remediation**: Blocklist ERC-777 tokens at creation time (check ERC1820 registry for `ERC777TokensSender`/`Recipient` interface). OR make the factory's allowance-pull path atomic across all clones with a factory-level transient lock.

### H-7 — EIP-1271 `isValidSignature` accepts any ECDSA signature the owner/operator ever produced
**Location**: `YieldVault.sol:384-390`
**Impact**: No domain separator, no typed-data binding, no purpose scoping. Any operator-signed hash from any dApp on any chain can be replayed to the vault. Cross-chain replay works trivially (no chainId in the envelope); cross-dApp replay works whenever two dApps compute the same hash.
**Scenario**: Operator signs "Login to X" via a wallet modal → adversary replays the hash+sig to `vault.isValidSignature` → Bebop accepts it as vault consent if the attacker can contrive a JAM order hashing to the same 32 bytes.
**Remediation**: Wrap verified hashes inside a vault-specific EIP-712 domain separator binding `chainId, address(this), purpose`.

### H-8 — `requestRedeem(shares, controller, owner)` lets operator route controller to attacker
**Location**: `YieldVault.sol:219-233`
**Impact**: Caller auth is `msg.sender == owner || _operators[owner][msg.sender]`, but `controller` is unvalidated. An operator that Alice approved can call `requestRedeem(aliceShares, controller=bob, owner=alice)`. Shares leave Alice, `_pendingRedeemShares[bob]` increments, Bob later `redeem(shares, receiver=bob, controller=bob)` — Alice's assets go to Bob.
**Remediation**: `require(controller == owner)` in `requestRedeem`, OR require a separate `authorizedController[owner][controller]` grant.

### H-9 — Redeem price snapshot at `fulfillRedeem`-time, not `requestRedeem`-time
**Location**: `YieldVault.sol:229-252`
**Impact**: `_pendingRedeemShares[controller] +=` is additive; `fulfillRedeem` calls `_convertToAssets(totalPending, Floor)` once. Users can time multiple requests to ride a favorable share-price move between their own requests and fulfilment, getting a free option on the vault's NAV in either direction.
**Remediation**: Store `_pendingRedeemAssets[controller]` snapshotted at request time (EIP-7540 allows either model).

### H-10 — `Collateral.redeem(account, amount)` is unauthenticated — forced exit / snapshot manipulation
**Location**: `Collateral.sol:366-373`
**Impact**: Natspec explicitly allows "anyone" to call for "keeper sweeps". Third party can force a victim's exit at a chosen moment, at the worst pro-rata split. In settled mode this locks in the ratio between `collateral-reserve` and `consideration` at adversary-chosen timing.
**Remediation**: Require `msg.sender == account || factory.approvedOperator(account, msg.sender)`. Keeper workflows already have `sweep` for zero-balance idempotency.

### H-11 — `sweep(holders[])` DoS via reverting holder or blacklist
**Location**: `Collateral.sol:520-533`
**Impact**:
1. Any holder with a reverting `fallback` contract address, or a USDC/USDT-blacklisted address, makes the whole batch revert.
2. Unbounded `holders.length` — attacker can grief with huge arrays.
**Scenario**: Mallory deploys revert-on-receive contract, transfers 1 wei Collateral to it pre-expiry. Post-expiry, every keeper `sweep([...])` that includes Mallory's address reverts; keepers must discover and exclude.
**Remediation**: Low-level call per holder with try/catch + `SweepFailed(holder)` event to skip failures; bound `holders.length`.

### H-12 — Clone initialization (currently safe but fragile)
**Location**: `Factory.sol:162-182`; templates' `_disableInitializers()` at construction
**Impact**: Template is protected. Clones are cloned + initialized atomically in one tx, so no front-run gap. Any future helper that splits clone and init across txs opens a front-run hijack.
**Remediation**: Keep the atomic invariant; add regression test for double-init revert.

---

## Medium

### M-1 — FOT check in `exercise` uses `< consAmount` instead of `!= consAmount`
**Location**: `Collateral.sol:336` (loose) vs `Collateral.sol:269` (strict on mint)
**Impact**: Exercise accepts MORE than `consAmount` arriving. Tokens that mint-on-transfer (airdrop tokens) or hook-donate bypass the check; internal accounting diverges from actual balance.
**Remediation**: Use strict equality on exercise too.

### M-2 — Individual blacklist bricks single short position
**Location**: `Collateral.sol:506-515`
**Impact**: A short holder blacklisted on USDC cannot `redeem`/`sweep` — all their collateral is stuck until they transfer their Collateral-token balance to a clean address (which itself requires transfers to be possible).
**Remediation**: `redeemTo(address receiver)` to let users route payouts away from their blacklisted address.

### M-3 — `_redeemPair` fallback leaks consideration in European mode
**Location**: `Collateral.sol:288-307, 439-450`
**Impact**: `_redeemConsideration` internal (used by the waterfall) does not check `isEuro`, only the public `redeemConsideration` does. If a European option's collateral balance is ever short (defense-in-depth scenario), the fallback silently pays consideration even though European options are documented as "pair redeem only".
**Remediation**: Add `if (isEuro) revert EuropeanExerciseDisabled();` to `_redeemConsideration` internal, OR explicit guard in waterfall.

### M-7 — Blocklist does not freeze pre-block options
**Location**: `Factory.sol:158, 333-344`
**Impact**: When a token is blocklisted mid-life, existing options against it remain fully functional, including third-party `Option.mint(victim, amount)` via H-1. User allowances stay exposed.
**Remediation**: Add `Factory.lockOption(option)` owner path to freeze a pre-block option.

### M-9 — Oracle detection is spoofable
**Location**: `Factory.sol:237-246`
**Impact**: `_deployOracle` accepts any contract whose `expiration()` returns the matching timestamp OR whose `token0()` doesn't revert. Attacker deploys a fake oracle returning `p.expirationDate`, lists a European option, then flips the oracle's spot at settlement to mint arbitrary ITM payouts.
**Remediation**: Owner-curated `trustedOracles[address]` set, OR ERC-165 interface ID check, OR hardcoded Uniswap v3 factory + Chainlink feed registry.

### M-11 — Exercise FOT check bypassable via hook-donated consideration
**Location**: `Collateral.sol:333-336`
**Impact**: Token hook during `safeTransferFrom` can donate extra `consideration` from another attacker address, making `consBalance - consBefore >= consAmount` pass even when `caller` only paid a fraction.
**Remediation**: Also check `caller`-side balance delta; blocklist ERC-777.

---

## Low / Informational

- **M-5 / L-1**: `YieldVault.renounceOwnership` not overridden — owner can abandon vault, freezing `fulfillRedeem`. Override to revert like `Option.renounceOwnership`.
- **M-6**: Factory `Approval(token, owner, amount)` event has confusing overlap with ERC-20 `Approval`. Rename to `FactoryAllowanceSet`.
- **M-8**: Factory uses one-step `Ownable` — typo on `transferOwnership` loses blocklist control. Use `Ownable2Step`.
- **M-10**: `uint160` truncation in `Factory.transferFrom` is only defended at the Collateral layer — promote to `uint256` + factory-level revert on overflow for defense in depth.
- **L-2**: `Option.decimals()` re-queries the collateral token on every call — cache at init like Collateral does.
- **L-5**: `cleanupOptions` requires `bal == 0` — dust amounts leave options tracked forever.
- **I-1**: "Permit2 compatibility" is only `uint160` bounds; no actual `permitTransferFrom` integration.
- **I-2**: EIP-2612 `permit` not wired into factory — users with permit-capable tokens still need two signatures.
- **I-4/I-5**: Positive findings — `forceApprove` used correctly; `fulfillRedeem` `_totalClaimableAssets` isolation is sound.
- **I-7**: Option `Ownable` one-step is acceptable (only `lock`/`unlock` is owner-gated).

---

## Cross-cutting recommendations

1. **Fix Factory allowance model** — Either scope to `(token, owner, option)` or gate `Option.mint(account, amount)` on `msg.sender == account || approvedOperator(account, msg.sender)`. Closes H-1, H-2, H-6, M-7 in one stroke.
2. **Split YieldVault roles** — `onlyTrader` (execute with allowlisted target+selector) vs `onlyOwner` (approve, addOption, setupFactoryApproval). Closes C-1, C-2, C-3 defense in depth.
3. **Token compatibility matrix** — Blocklist rebasing + ERC-777 + pausable tokens by default; require owner approval to allow.
4. **EIP-1271 domain binding** — Replace raw `ecrecover` with an EIP-712 envelope specific to the vault (chainId + `address(this)` + purpose tag).
5. **Third-party redeem/sweep auth** — Gate post-expiry `redeem(account)` on `msg.sender == account || approvedOperator`.
