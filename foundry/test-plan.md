# Test Suite Plan

## Cleanup: Remove Redundancies

1. **Delete `test_RedeemWithAddress`** — identical to `test_Redeem1` after `redeem(address,uint256)` removal
2. **Delete `test_ShortOptionSweepMultipleUsers`** — identical to `test_Sweep` (single user, misleading name)
3. **Remove `t1`/`t2` modifiers and `consoleBalances()`** — debug artifacts adding noise to output
4. **Remove commented-out code** in `test_ExerciseWithInsufficientConsideration`

## Cleanup: Improve Existing Tests

5. **Add specific error selectors** to all 9 bare `vm.expectRevert()` calls:
   - `test_ZeroAmountMint` → `InvalidValue.selector`
   - `test_ZeroAmountExercise` → `InvalidValue.selector`
   - `test_ZeroAmountRedeem` → `InvalidValue.selector`
   - `test_InsufficientBalanceExercise` → `InsufficientBalance.selector`
   - `test_InsufficientBalanceRedeem` → `InsufficientBalance.selector`
   - `test_DoubleExercise` → `InsufficientBalance.selector`
   - `test_ExerciseAfterExpiration` → `ContractExpired.selector`
   - `test_MintAfterExpiration` → `ContractExpired.selector`
   - `test_RedeemAfterExpiration` → `ContractNotExpired.selector` (redeem requires pre-expiration)
6. **Add assertions** to `test_Details`, `test_CollateralData`, `test_ConsiderationData`

## New Tests: HIGH Priority

### Put options (currently zero coverage)
7. **`test_PutMintAndExercise`** — create put option (isPut=true), mint, exercise, verify collateral/consideration flow is reversed
8. **`test_PutNameDisplay`** — verify `name()` shows inverted strike for puts
9. **`test_PutStrikeZeroName`** — verify `name()` doesn't revert when strike=0 on put

### Different token decimals (currently only 18/18)
10. **`test_MixedDecimals_6_18`** — create option with 6-decimal collateral (like USDC) and 18-decimal consideration, verify `toConsideration`/`toCollateral` conversions
11. **`test_MixedDecimals_18_6`** — reverse: 18-decimal collateral, 6-decimal consideration
12. **`test_MixedDecimals_ExerciseFlow`** — full mint→exercise→redeem with mixed decimals

### Non-trivial strike prices (currently only 1:1)
13. **`test_Strike2000_Exercise`** — create option with strike=2000e18 (like ETH/USDC call), verify correct consideration amount required
14. **`test_Strike2000_ToConsideration`** — verify conversion math at realistic strike
15. **`test_Strike2000_ToCollateral`** — verify inverse conversion

## New Tests: MEDIUM Priority

### Fee mechanics
16. **`test_AdjustFee`** — owner adjusts fee, verify new fee applies on next mint
17. **`test_AdjustFeeMaxExceeded`** — fee > MAXFEE reverts with `InvalidValue`
18. **`test_AdjustFeeEvent`** — verify `FeeUpdated` event emitted with correct old/new values
19. **`test_ClaimFees`** — mint tokens, verify fees accumulated, claim them, verify transfer to factory
20. **`test_FeeSegregation`** — mint tokens, verify redeemers cannot consume fee balance (the fix from audit #6)

### Access control
21. **`test_NonOwnerCannotAdjustFee`** — non-owner calling `adjustFee` reverts
22. **`test_NonOwnerCannotLock`** — non-owner calling `lock` reverts
23. **`test_NonOwnerCannotUnlock`** — non-owner calling `unlock` reverts
24. **`test_NonOwnerCannotClaimFees`** — non-owner calling `claimFees` reverts

### Factory allowance
25. **`test_FactoryAllowanceDecrement`** — after mint, factory allowance decremented by collateral amount
26. **`test_FactoryAllowanceInfinite`** — `type(uint256).max` allowance not decremented
27. **`test_FactoryAllowanceInsufficient`** — mint with insufficient factory allowance reverts

### Name/Symbol output
28. **`test_OptionName`** — verify name format includes collateral symbol, consideration symbol, strike, expiry
29. **`test_RedemptionName`** — verify redemption token name format

## New Tests: LOW Priority

### Event emissions
30. **`test_MintEmitsEvent`** — verify `Mint` event
31. **`test_ExerciseEmitsEvent`** — verify `Exercise` event
32. **`test_RedeemEmitsEvent`** — verify `Redeemed` event
33. **`test_LockEmitsEvent`** — verify `ContractLocked` event

### Batch operations
34. **`test_CreateOptionsBatch`** — factory `createOptions` with multiple params, verify all deployed

### Fuzz tests
35. **`testFuzz_MintAndRedeem(uint256 amount)`** — fuzz mint amount, redeem full, verify balances zero out
36. **`testFuzz_MintAndExercise(uint256 amount)`** — fuzz mint then exercise, verify consideration transferred
37. **`testFuzz_TransferAutoRedeem(uint256 mintAmt, uint256 transferAmt)`** — fuzz auto-redeem behavior

## Other Test Files

### Delete or archive
- **`FactoryCriticalIssues.t.sol`** — entirely commented out, serves as documentation only. Either uncomment and fix or move to docs.
- **`GasErrors.t.sol`** — utility comparison, not protocol tests. Could move to a `benchmarks/` folder.
- **`CloneGas.t.sol`** — `test_CreateOptionFullGas` is a placeholder. Either complete or delete.

### Fix incomplete
- **`GasBreakdown.t.sol`** — `test_GasBreakdown_Step4_StorageOperations` is incomplete (never reads gasleft)
- **`GasAnalysis.t.sol`** — `test_Gas_Option_RedeemWithAddress` was updated to `redeem(5)` but test name is now misleading. Rename to `test_Gas_Option_Redeem_5Tokens`.
