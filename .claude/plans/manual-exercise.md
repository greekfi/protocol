# Manual-Exercise Branch — No-Oracle Settlement Plan

## Context

The protocol currently supports two settlement modes (American non-settled and oracle-settled European/American), tied together by an oracle that snaps a settlement price post-expiry. The `auto-settlements` branch (formerly `v2-updates`) extends that with cash-settlement-by-default + a `claim` overload set + an injectable `ISettlementSwapper`.

This branch (`manual-exercise`, off `origin/main`) is the opposite move: **strip oracles entirely** and reduce settlement to two pure rules:

1. **American** — exercise allowed any time before expiration.
2. **European-style window** — exercise also allowed for `EXERCISE_WINDOW` hours after expiration. After the window closes, only short-side redemption is allowed.

No oracle is ever consulted. The holder decides off-chain whether ITM is profitable and pays strike to exercise. The protocol just enforces the timing window and the 1:1 collateral invariant.

## Branch / repo layout

- `auto-settlements` — every oracle / cash-settlement / `claim` / swapper feature lives here. Existing v2 work + audit fixes go on this branch.
- `manual-exercise` — this branch. Strip oracles, add post-expiry exercise window. Smaller surface, easier to audit, no external trust.

Pick one to deploy or list both as separate option flavors at the Factory level later.

## Surface to remove (from `Option.sol`)

- `import { IPriceOracle } from "./oracles/IPriceOracle.sol"`
- `oracle()`, `isSettled()`, `settlementPrice()` views
- `settle(bytes hint)` external
- `claim()`, `claim(uint256)`, `claimFor(address)` and overloads
- `Settled`, `Claimed` events
- `NoOracle`, `EuropeanExerciseDisabled` errors
- `isEuro()` view
- All branching on `isEuro` / `oracle == address(0)` inside `_settledTransfer`, `transfer`, `transferFrom`, `exercise`

## Surface to remove (from `Collateral.sol`)

- `oracle` storage + getter
- `isEuro` storage + getter
- `settlementPrice` storage
- `_isSettled` flag
- `optionReserveRemaining` storage
- `settle()` external
- `_settle()` internal
- `_claimForOption(...)` (only used by Option.claim)
- `_redeemSettled(...)` post-expiry settled branch
- All `isItm` / oracle reads in `redeem` / `sweep`

## Surface to remove (from `Factory.sol`)

- `oracleSource` and `isEuro` from `CreateParams`
- `_deployOracle(...)` and the entire branch matching pre-deployed oracles vs. UniV3 pools
- The blocklist still applies to the underlying tokens; oracle blocklist not needed.

## Surface to remove from `interfaces/`

- Drop oracle/settle/claim signatures from `IOption.sol`, `ICollateral.sol`, `IFactory.sol`
- Delete `oracles/IPriceOracle.sol`
- Delete `oracles/UniV3Oracle.sol`

## Surface to add

Two things only:

1. **Per-option exercise deadline.** On `Collateral.init` (called from `Option.init`):
   ```solidity
   uint40 public immutable exerciseDeadline;   // = expirationDate + EXERCISE_WINDOW
   ```
   `EXERCISE_WINDOW` lives as a Factory-level constant or a `uint40 windowSeconds` param on `CreateParams`. Sensible default: **24 hours** (mirrors CBOE retail).

2. **Modifiers.**
   ```solidity
   modifier withinExerciseWindow() {
       if (block.timestamp >= exerciseDeadline) revert ExerciseWindowClosed();
       _;
   }
   modifier afterExerciseWindow() {
       if (block.timestamp < exerciseDeadline) revert ExerciseWindowOpen();
       _;
   }
   ```
   - `Option.exercise(...)`: `withinExerciseWindow` (replaces the old `notExpired`)
   - `Collateral.redeem(account, amount)` (post-expiry pro-rata): `afterExerciseWindow` (replaces the old `expired`)
   - `Collateral.sweep(...)`: `afterExerciseWindow`
   - `Collateral._redeemPair(...)`: stays available the entire lifetime (pair redemption is always valid; it doesn't depend on the window)

## What stays unchanged

- `Option.mint`, `Option.transfer`, `Option.transferFrom`, `Option.redeem` (pair) — unchanged.
- `Collateral._redeemPair`, `_redeemPairInternal`, `_redeemProRata` — unchanged.
- Factory `transferFrom`, blocklist, `setApprovalForAll`/`approveOperator` — unchanged.
- `enableAutoMintRedeem` opt-in (auto-mint on transfer / auto-redeem on receive) — kept by default. It's a UX flag, unrelated to oracle settlement. **Open question** below.

## Settled decisions

1. **Auto-mint hooks → narrow.** Keep `enableAutoMintRedeem` and `_settledTransfer`. Only the oracle-driven path (`settle` / `claim`) is removed. Auto-mint stays as a user-opt-in UX feature, unrelated to settlement.
2. **Exercise window → 8 hours.** `EXERCISE_WINDOW = 8 hours = 28800 seconds`. Holders have 8 hours after `expirationDate` to call `exercise` before the window closes and shorts can redeem.
3. **Window location → per-option.** `windowSeconds` lives on `CreateParams`, default 8 hours but settable at creation. Stored as `uint40 public immutable exerciseDeadline = expirationDate + windowSeconds` on the Collateral clone.

## Tests to remove / rewrite

- `OptionSettlement.t.sol` — entirely removable (it's all about oracle-settled mode).
- `Option.t.sol` — drop the European / `claim` blocks; keep the American + pair-redeem suites.
- `Factory.t.sol` — drop the `oracleSource` / `isEuro` cases.
- `YieldVault.t.sol` — likely fine; YieldVault is itself oracle-free and Bebop-driven.

Add a new `ExerciseWindow.t.sol`:
- Exercise pre-expiry: works
- Exercise during window: works
- Exercise after window: reverts `ExerciseWindowClosed`
- Redeem during window: reverts `ExerciseWindowOpen`
- Redeem after window: pro-rata works

## What this gets you

- **No oracle dependency** — eliminates the entire C-1 / H-3 / H-5 / H-6 / H-8 family of audit findings (oracle bricking, spoofable oracle, Chainlink hardening).
- **Smaller contracts** — easier audit, lower deploy gas, tighter cognitive model.
- **Holder-decides settlement** — holder watches off-chain spot, exercises if profitable. No protocol decision risk.
- **Slightly worse UX for retail** — holder has to actually do something during the window or forfeit. Mitigate with a keeper running `exerciseFor` (which we'd port over from `auto-settlements` minus the cash-conversion bits).

## Concrete next steps

1. **Implement the surgery** on `manual-exercise`. Single-PR diff:
   - Delete `foundry/contracts/oracles/` directory entirely.
   - Strip the surface listed above from `Option.sol` / `Collateral.sol` / `Factory.sol`.
   - Strip oracle/settle/claim from `interfaces/IOption.sol`, `ICollateral.sol`, `IFactory.sol`.
   - Add `windowSeconds` to `CreateParams` (default 8 hours = 28800).
   - Add `uint40 public immutable exerciseDeadline` to Collateral, set in `init`.
   - Add `withinExerciseWindow` and `afterExerciseWindow` modifiers.
   - Update tests (drop OptionSettlement.t.sol; trim Option.t.sol/Factory.t.sol; add ExerciseWindow.t.sol).
   - Update CLAUDE.md to reflect the new (much shorter) lifecycle.
2. **Carry-over from `auto-settlements`** — `exerciseFor` (single + array) for the keeper UX. The cash-settlement / swapper / `claim` path is *not* carried over.

## Branch coexistence

Two branches diverge from main:
- `auto-settlements` (more features, larger trust surface): oracle-settled options, cash settlement, swapper.
- `manual-exercise` (this branch): no oracle, exercise window only.

If you eventually want both to coexist on mainnet, the cleanest way is a separate Factory deployment per flavor. The two flavors share the underlying ERC20 mechanics; the divergence is in the templates only.
