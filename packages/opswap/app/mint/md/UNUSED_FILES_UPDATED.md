# Unused Files in /mint Directory (Updated)

All files marked with ⚠️ are NOT being used and can be safely deleted.

## ⚠️ COMPLETELY UNUSED - Safe to Delete

### Deprecated Action Components
- ⚠️ `action.tsx` - Old combined action component (replaced by ExerciseAction.tsx, RedeemAction.tsx)
- ⚠️ `components/MintAction.tsx` - Original mint component
- ⚠️ `components/MintActionSimple.tsx` - Simple auto-approval version (replaced by MintActionClean.tsx)
- ⚠️ `components/MintActionRefactored.tsx` - Flow-based approach
- ⚠️ `components/MintActionPresentational.tsx` - Presentational component for flow

### Deprecated Hooks - Replaced by Transaction Hooks
- ⚠️ `hooks/useMint.ts` - Original combined approval + mint
- ⚠️ `hooks/useMintWithApprovals.ts` - Auto-approval mint (replaced by component logic)
- ⚠️ `hooks/useMintAction.ts` - Mint executor (replaced by hooks/transactions/useMintTransaction.ts)
- ⚠️ `hooks/useApprove.ts` - Approve executor (replaced by hooks/transactions/useApproveERC20.ts and useApproveFactory.ts)
- ⚠️ `hooks/useMintFlow.ts` - Flow-based state management
- ⚠️ `hooks/useApproval.ts` - Complex approval flow

### Deprecated Hooks - Replaced by New Versions
- ⚠️ `hooks/useGetOption.ts` - Replaced by useOption.ts
- ⚠️ `hooks/useGetOptions.ts` - Replaced by useOptions.ts
- ⚠️ `hooks/useGetDetails.ts` - Old details hook
- ⚠️ `hooks/useIsExpired.ts` - Now handled in useOption.ts

### Permit2 Related (Not Implemented)
- ⚠️ `hooks/usePermit2.ts` - Permit2 not implemented
- ⚠️ `hooks/useAllowanceCheck.ts` - Replaced by useAllowances.ts
- ⚠️ `hooks/permit2abi.ts` - Permit2 ABI not needed

### Unused UI Components
- ⚠️ `Balance.tsx` - Token balance display
- ⚠️ `components/OptionInterface.tsx` - Old option interface
- ⚠️ `components/TokenBalance.tsx` - Only used by OptionInterface.tsx
- ⚠️ `components/walletSelector.tsx` - Using RainbowKit instead
- ⚠️ `account.tsx` - Using RainbowKit instead
- ⚠️ `contractInfo.tsx` - Contract info display
- ⚠️ `config.ts` - Using scaffold-eth config

### Utilities
- ⚠️ `hooks/useTime.ts` - Time display utility

### Can Delete When action.tsx is Removed
- `components/TooltipButton.tsx` - Only used by deprecated action.tsx
- `components/TokenBalanceNow.tsx` - Only used by deprecated action.tsx

## ✅ CURRENTLY USED FILES

### Active Pages & Layout
- ✅ `page.tsx` - Main page
- ✅ `layout.tsx` - Layout wrapper

### Active Components
- ✅ `CreateMany.tsx` - Create multiple options
- ✅ `Details.tsx` - Option details display
- ✅ `Navbar.tsx` - Navigation bar
- ✅ `Selector.tsx` - Option selector dropdown
- ✅ `components/DesignHeader.tsx` - Used by CreateMany

### Active Action Components (Clean Architecture)
- ✅ `components/MintActionClean.tsx` - Mint options
- ✅ `components/ExerciseAction.tsx` - Exercise options
- ✅ `components/RedeemAction.tsx` - Redeem pairs

### Active Transaction Hooks (Pure Write Operations)
- ✅ `hooks/transactions/useApproveERC20.ts` - ERC20 token approval
- ✅ `hooks/transactions/useApproveFactory.ts` - Factory approval
- ✅ `hooks/transactions/useMintTransaction.ts` - Mint transaction
- ✅ `hooks/transactions/useExerciseTransaction.ts` - Exercise transaction
- ✅ `hooks/transactions/useRedeemTransaction.ts` - Redeem transaction

### Active Data Hooks (Pure Read Operations)
- ✅ `hooks/useOption.ts` - Get single option details
- ✅ `hooks/useOptions.ts` - Get list of all options
- ✅ `hooks/useAllowances.ts` - Check allowances
- ✅ `hooks/useCreateOption.ts` - Create new options
- ✅ `hooks/useContracts.ts` - Get contract instances
- ✅ `hooks/useContract.ts` - Legacy contract hook (used by CreateMany/useTokenMap)
- ✅ `hooks/useTokenMap.ts` - Token list management
- ✅ `hooks/constants.ts` - Shared constants
- ✅ `hooks/types/index.ts` - TypeScript types

### Partially Used
- ⚠️ `hooks/useTransactionFlow.ts` - Only getStepLabel() is used by CreateMany.tsx

## Clean Architecture - How Files Are Used

### page.tsx → Three Clean Action Components
```
page.tsx
├── MintActionClean.tsx
│   ├── useOption() - fetch data
│   ├── useAllowances() - fetch allowances
│   ├── useApproveERC20() - execute approval
│   ├── useApproveFactory() - execute approval
│   └── useMintTransaction() - execute mint
│
├── ExerciseAction.tsx
│   ├── useOption() - fetch data
│   ├── useAllowances() - fetch allowances
│   ├── useApproveERC20() - execute approval
│   └── useExerciseTransaction() - execute exercise
│
└── RedeemAction.tsx
    ├── useOption() - fetch data
    └── useRedeemTransaction() - execute redeem
```

### Pattern
- **Data hooks** = Pure reads (useOption, useAllowances, useOptions)
- **Transaction hooks** = Pure writes (useApproveERC20, useMintTransaction, etc.)
- **Components** = All logic (decide when to approve, when to execute)

## Summary

Total files: ~45
- ✅ **Currently used**: ~25 files
- ⚠️ **Can be deleted**: ~20 files

The new clean architecture uses:
- 3 action components (Mint, Exercise, Redeem)
- 5 transaction hooks (2 approvals + 3 actions)
- 3 data hooks (useOption, useOptions, useAllowances)
- Everything else is just contract helpers and types
