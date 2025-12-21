# Unused Files in /mint Directory

This document identifies files that are NOT currently being used in the application.

## ⚠️ COMPLETELY UNUSED - Safe to Delete

### Deprecated Mint Components (Replaced by MintActionSimple.tsx)
- `components/MintAction.tsx` - Original mint component before refactoring
- `components/MintActionRefactored.tsx` - Flow-based approach (deprecated)
- `components/MintActionPresentational.tsx` - Presentational component for flow approach (deprecated)

### Deprecated Hooks (Replaced by newer versions)
- `hooks/useMint.ts` - Original combined approval + mint hook (replaced by useMintWithApprovals.ts)
- `hooks/useMintFlow.ts` - Flow-based state management (deprecated in favor of auto-approval)
- `hooks/useApproval.ts` - Complex approval flow hook (replaced by simpler useApprove.ts)
- `hooks/useGetOption.ts` - Old option data hook (replaced by useOption.ts)
- `hooks/useGetOptions.ts` - Old options list hook (replaced by useOptions.ts)
- `hooks/useGetDetails.ts` - Old details hook (unused)
- `hooks/useIsExpired.ts` - Expiration logic (now handled in useOption.ts)

### Permit2 Related (Not Implemented)
- `hooks/usePermit2.ts` - Permit2 signature-based approvals (not implemented)
- `hooks/useAllowanceCheck.ts` - Permit2 allowance checking (replaced by useAllowances.ts)
- `hooks/permit2abi.ts` - Permit2 ABI (not needed)

### Unused UI Components
- `Balance.tsx` - Token balance display component
- `components/OptionInterface.tsx` - Old option interface
- `components/TokenBalance.tsx` - Only used by unused OptionInterface.tsx
- `components/walletSelector.tsx` - Custom wallet selector (using RainbowKit instead)
- `account.tsx` - Custom account component (using RainbowKit instead)
- `contractInfo.tsx` - Contract info display
- `config.ts` - Custom wagmi config (using scaffold-eth config instead)

### Unused Utilities
- `hooks/useTime.ts` - Time display utility (unused)

## ⚠️ PARTIALLY UNUSED

### `hooks/useTransactionFlow.ts`
- **Status**: Partially used
- **Used by**: CreateMany.tsx (only the `getStepLabel()` function)
- **Unused**: The `useTransactionFlow` hook itself
- **Note**: Could extract just the `getStepLabel()` function to constants.ts

### `hooks/useContract.ts`
- **Status**: Partially used
- **Used by**: action.tsx, useTokenMap.ts
- **Note**: Most other hooks now use useContracts.ts instead
- **Keep**: Still needed for action.tsx

## ✅ CURRENTLY USED FILES

### Active Components
- `page.tsx` - Main page
- `CreateMany.tsx` - Create multiple options
- `Details.tsx` - Option details display
- `Navbar.tsx` - Navigation bar
- `Selector.tsx` - Option selector dropdown
- `action.tsx` - Exercise/Redeem actions
- `layout.tsx` - Layout wrapper
- `components/MintActionSimple.tsx` - **ACTIVE** mint component with auto-approvals
- `components/DesignHeader.tsx` - Used by CreateMany
- `components/TooltipButton.tsx` - Used by action.tsx
- `components/TokenBalanceNow.tsx` - Used by action.tsx

### Active Hooks
- `hooks/useOption.ts` - Get single option details
- `hooks/useOptions.ts` - Get list of all options
- `hooks/useAllowances.ts` - Check ERC20 and factory allowances
- `hooks/useApprove.ts` - Execute approval transactions
- `hooks/useMintAction.ts` - Execute mint transaction
- `hooks/useMintWithApprovals.ts` - **ACTIVE** auto-approval mint flow
- `hooks/useCreateOption.ts` - Create new options
- `hooks/useContracts.ts` - Get contract instances
- `hooks/useContract.ts` - Legacy contract hook (still used by action.tsx)
- `hooks/useTokenMap.ts` - Token list management
- `hooks/constants.ts` - Shared constants
- `hooks/types/index.ts` - TypeScript types

## Recommended Actions

1. **Delete all "COMPLETELY UNUSED" files** - They are not imported anywhere and safe to remove
2. **Keep "PARTIALLY UNUSED" files** - They have at least one active usage
3. **Keep all "CURRENTLY USED" files** - These are actively imported and used

## File Usage Tree

```
page.tsx
├── CreateMany.tsx
│   ├── components/DesignHeader.tsx
│   ├── hooks/useTokenMap.ts
│   │   └── hooks/useContract.ts
│   ├── hooks/useCreateOption.ts
│   │   └── hooks/useContracts.ts
│   └── hooks/useTransactionFlow.ts (getStepLabel only)
├── Details.tsx
├── Navbar.tsx
├── Selector.tsx
├── action.tsx
│   ├── components/TokenBalanceNow.tsx
│   ├── components/TooltipButton.tsx
│   ├── hooks/useContract.ts
│   └── hooks/useContracts.ts
├── components/MintActionSimple.tsx ✅ ACTIVE
│   ├── hooks/useOption.ts
│   │   ├── hooks/useContracts.ts
│   │   └── hooks/types/index.ts
│   └── hooks/useMintWithApprovals.ts ✅ ACTIVE
│       ├── hooks/useOption.ts
│       ├── hooks/useAllowances.ts
│       │   ├── hooks/useContracts.ts
│       │   └── hooks/types/index.ts
│       ├── hooks/useApprove.ts
│       │   ├── hooks/useContracts.ts
│       │   └── hooks/constants.ts
│       └── hooks/useMintAction.ts
│           └── hooks/useContracts.ts
├── hooks/useOption.ts
└── hooks/useOptions.ts
    └── hooks/useContracts.ts
```
