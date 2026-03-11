# OpHook + OptionVault Review (PR #33)

## Critical Issues

### 1. Oracle manipulation via `slot0()` (OpHook:323)
`getCollateralPrice` reads `slot0()` from the Uniswap v3 price pool — trivially manipulable in a single transaction via flash loans. Attacker can flash-loan to move price, buy cheap options, restore price. Should use TWAP via `observe()`.

### 2. Arbitrary external call in `swapToCollateral` (OptionVault:284-298)
Owner-only but takes arbitrary `router` + `swapData`, does `router.call(swapData)`. Effectively unrestricted call from vault. Approval never reset after call. Add `forceApprove(router, 0)` after, consider whitelisted router.

### 3. `mintAndDeliver` delivers ALL option tokens (OptionVault:187-188)
`optionsDelivered = IERC20(option).balanceOf(address(this))` sends entire balance, not just minted amount. Should snapshot before mint and deliver only the delta.

### 4. `initPool` — `collateralPricePool` silently overwritten (OpHook:404)
Second call with same collateral but different price feed overwrites oracle for all existing pools using that collateral.

## High Severity

### 5. No slippage protection on `swapForOption` (OpHook:221-239)
No `minOptionsOut` parameter. Price can change between tx submission and execution.

### 6. Option amount vs collateral amount mismatch (OpHook:236, 271)
`mintAndDeliver` takes "collateral to commit" but hook passes `p.optionAmount` (desired options). Fees cause buyer to receive fewer options than priced for.

### 7. ERC4626 first-depositor/donation attack (OptionVault:127-129)
`totalAssets()` includes raw `balanceOf`. Classic donation attack possible. Need virtual share offset.

## Medium Severity

### 8. Buyback path requires hook to hold cash (OpHook:285)
Buybacks send USDC from hook balance. Competes with `sweepPremiumToVault`. No mechanism to reserve funds.

### 9. `allPools` grows forever (OpHook:93, 347-357)
`getPrices` iterates all pools. Expired/dead pools never removed. Gas grows linearly.

### 10. `_beforeAddLiquidity` / `_beforeDonate` wrong parameter types (OpHook:291-305)
Both take `SwapParams calldata` — should be `ModifyLiquidityParams` and donate params respectively.

### 11. `setupFactoryApproval` no access control (OptionVault:316-319)
Anyone can call. Not exploitable but sloppy.

### 12. `swapToCollateral` doesn't require collateral increased (OptionVault:300)
`collGained` computed but never checked > 0.

### 13. `initPool` doesn't validate option.collateral() matches `collateral` param (OpHook:359-407)

## Low / Design

### 14. Deposits/withdrawals not pausable
`pause()` only blocks `mintAndDeliver` and `pairRedeem`, not ERC4626 deposit/withdraw. May be intentional.

### 15. Premium flow is indirect and owner-dependent
Premiums accumulate in hook. Owner must manually sweep then swap. LPs earn nothing until owner acts.

### 16. Dual entry points (`swapForOption` direct + Uni v4 pool)
Different settlement flows and trust assumptions. Increases attack surface.

### 17. `OptionPrice` volatility is owner-set, not market-derived
Centralization risk. Fine for launch but worth noting.

---

# StrategyVault Refactor Plan

## Target Architecture

```
Trader --swap--> OpHook --getQuote/mintAndDeliver/pairRedeem--> StrategyVault (IStrategyVault)
                   (thin router, no pricing)                     |-- ERC4626 vault (LP deposits)
                                                                 |-- Pricing (Black-Scholes, TWAP oracle)
                                                                 |-- Strategy (strikes/exps, rolling)
                                                                 |-- Execution (mint/redeem/settle)
                                                                 |-- Premium management

OptionFactory (unchanged) <-- StrategyVault creates options via factory
```

## New Files

### 1. `contracts/interfaces/IStrategyVault.sol` — Interface
The hook and external consumers program against this interface.
- `getQuote(address option, uint256 inputAmount, bool cashForOption) -> (uint256 outputAmount, uint256 price)`
- `mintAndDeliver(address option, uint256 optionAmount, address buyer) -> uint256 delivered`
- `pairRedeem(address option, uint256 amount)`
- `handleSettlement(address option)`
- `receivePremium(address token, uint256 amount)`
- `rollOptions(address expiredOption)` — permissionless, first caller gets bounty
- `createOption(uint96 strike, uint40 expiration, bool isPut) -> address`
- `setVolatility(uint256)` / `setRiskFreeRate(uint256)` / `setTwapWindow(uint32)`
- `setStrategy(StrikeConfig[] calldata)` — configure auto-roll strike selection
- `setRollBounty(uint256)` — configure roll incentive amount
- `getCollateralPrice() -> uint256`
- View: `idleCollateral()`, `utilizationBps()`, `getVaultStats()`, `getPositionInfo()`, `activeOptions()`

### 2. `contracts/libraries/BlackScholes.sol` — Pure math library
Extract from OptionPrice.sol: `blackScholesPrice`, `ln`, `log2`, `expNeg`, `normCdf`, `mul18`, `div18`.
Keeps StrategyVault under 24KB contract size limit. Gas-neutral vs internal functions.

### 3. `contracts/StrategyVault.sol` — Implementation (implements IStrategyVault)
Inherits: ERC4626, Ownable, ReentrancyGuardTransient, Pausable

**Section 1: ERC4626 vault** (ported from OptionVault.sol)
- `totalAssets()` = idle + committed
- `maxWithdraw/maxRedeem` capped by idle
- First-depositor fix: override `_decimalsOffset()` to return 3
- `deposit/withdraw` with `whenNotPaused`

**Section 2: Pricing** (absorbed from OptionPrice.sol)
- `volatility`, `riskFreeRate`, `twapWindow` as owner-set state
- `getCollateralPrice()` uses v3 TWAP via `observe()` (fixes slot0 bug)
- `getQuote()` computes Black-Scholes price, converts cash <-> option amounts
- Uses BlackScholes library for math

**Section 3: Strategy + option lifecycle**
- `StrikeConfig { uint96 strikeOffset, bool isPut, uint40 duration }`
- `createOption()` — owner creates via factory
- `rollOptions(expiredOption)` — permissionless:
  1. Verify old option expired
  2. Settle if needed
  3. Compute new strikes from TWAP + config offsets
  4. Create new options via factory
  5. Auto-whitelist
  6. Pay `rollBounty` to `msg.sender` from vault collateral
- `rollBounty` — amount paid to first caller (denominated in collateral, owner-configurable)

**Section 4: Hook interaction** (ported from OptionVault.sol)
- `authorizedHooks` mapping (supports multiple hooks)
- `mintAndDeliver` — snapshots option balance before mint, delivers delta only
- Validates `option.collateral() == asset()`
- `pairRedeem`, `handleSettlement` — same logic, ported
- `receivePremium` — hook sends cash directly

**Section 5: Premium management**
- `swapToCollateral` — resets approval after swap, requires `collGained > 0`
- `setupFactoryApproval` — `onlyOwner`

### 4. Rewrite `contracts/OpHook.sol` — Thin router

**Remove:** All pricing logic, `OptionPrice` dependency, `allPools` unbounded array,
`collateralPricePool`, `sweepPremiumToVault`, cash accumulation.

**Simplified pool struct:**
```
struct PoolInfo {
    address optionToken;
    address cashToken;
    bool optionIsOne;
    IStrategyVault vault;
}
```

**Keep (modified):**
- `_beforeSwap` — calls `vault.getQuote()` for price, `vault.mintAndDeliver()` for buy, `vault.pairRedeem()` for sell. Cash goes directly to vault. Slippage via hookData.
- `initPool` — simplified params, vault provides price oracle, validates option collateral
- `swapForOption` — adds `minOptionsOut` param
- Fix `_beforeAddLiquidity`/`_beforeDonate` parameter types
- Bounded pool tracking with removal capability

## Files to Delete (after migration)
- `contracts/OptionVault.sol` → replaced by StrategyVault
- `contracts/OptionPrice.sol` → absorbed into BlackScholes library
- `contracts/OptionPoolVault.sol` → old vault, already superseded
- `contracts/interfaces/IOptionVault.sol` → replaced by IStrategyVault

## Test Files
- `test/StrategyVault.t.sol` — new comprehensive tests
- `test/BlackScholes.t.sol` — math library unit tests
- `test/OpHook.t.sol` — rewrite for new architecture

## Implementation Order

**Phase 1: Foundation**
1. `libraries/BlackScholes.sol` — extract math
2. `interfaces/IStrategyVault.sol` — define interface
3. `test/BlackScholes.t.sol` — verify math matches OptionPrice

**Phase 2: StrategyVault**
4. `StrategyVault.sol` — implement against interface
5. `test/StrategyVault.t.sol` — full coverage

**Phase 3: OpHook slim-down**
6. Rewrite `OpHook.sol`
7. Rewrite `test/OpHook.t.sol`

**Phase 4: Cleanup**
8. Delete old files, update deploy scripts

## Bug Fixes Incorporated

| # | Bug | Fix Location |
|---|-----|-------------|
| 1 | slot0() oracle manipulation | StrategyVault.getCollateralPrice() uses TWAP |
| 2 | Router approval not reset | StrategyVault.swapToCollateral() adds forceApprove(0) |
| 3 | Delivers all option tokens | StrategyVault.mintAndDeliver() snapshots delta |
| 4 | Price pool silently overwritten | Removed — vault owns its own oracle |
| 5 | No slippage protection | OpHook hookData encodes minOut; swapForOption adds param |
| 6 | Option/collateral amount mismatch | StrategyVault handles fee adjustment internally |
| 7 | First-depositor attack | StrategyVault._decimalsOffset() returns 3 |
| 8 | Hook must hold cash for buybacks | Hook never holds cash; vault provides directly |
| 9 | allPools grows forever | Bounded tracking with removal |
| 10 | Wrong hook param types | Fixed in OpHook rewrite |
| 11 | setupFactoryApproval open | onlyOwner in StrategyVault |
| 12 | swapToCollateral no gain check | require(collGained > 0) |
| 13 | No collateral validation | StrategyVault validates option.collateral() == asset() |

## Key Design Decisions

**Library vs embedded pricing:** Library. Keeps contract under 24KB, reusable, gas-neutral.

**Multiple hooks per vault:** Yes, via `authorizedHooks` mapping. Different fee tiers / cash tokens route to same vault.

**Rolling:** Permissionless `rollOptions()` — whoever calls first after expiry gets the bounty (paid from vault collateral). Bounty amount is owner-configurable. Computes new strikes from TWAP + configured offsets.

**Cash flow:** Hook never holds cash. Premiums go directly to vault. Buybacks funded from vault's cash holdings. Eliminates cash-starvation bug.

**TWAP window:** Configurable per vault, default 1800s. Owner adjusts based on collateral liquidity.

**Premium accounting:** Only counts as collateral after swap. No oracle-based valuation of cash holdings.

**Contract size risk:** StrategyVault inherits 4 OZ contracts + pricing + strategy. BlackScholes library saves ~4-5KB. `via_ir = true` already enabled.
