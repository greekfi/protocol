# 📦 ORIGINAL PROTOTYPE - Keep for Reference

## Status: ARCHIVED (Not Active, But Keep)

This `app/opswap` directory contains the **original prototype** that is **NOT being used** in the current application, but should be **kept for reference and history**.

## What's Being Used

**Only ONE file from this directory is being used:**

- `providers.tsx` - Imported by `/mint/layout.tsx` for Wagmi/RainbowKit setup

## What's NOT Being Used

All other files in this directory are unused:

- ❌ `page.tsx` - Old demo page (not routed)
- ❌ `layout.tsx` - Old layout
- ❌ `OptionInfo.tsx` - Old component
- ❌ `useAddOption.ts` - Old hook
- ❌ `useBuyOption.ts` - Old hook
- ❌ `useGetOptions.ts` - Old hook
- ❌ `useContract.ts` - Old hook
- ❌ `useAddress.ts` - Old hook
- ❌ `abi.ts` - Old ABI
- ❌ `constants.ts` - Old constants
- ❌ `not-found.tsx` - Old not found page
- ❌ `UniversalRouter.json` - Old ABI file
- ❌ `permit2.json` - Old ABI file

## Current Application Structure

```
app/
├── page.tsx              ✅ Landing page
├── layout.tsx            ✅ Root layout
├── mint/                 ✅ ACTIVE - Main application
│   ├── page.tsx          ✅ Mint/Exercise/Redeem interface
│   ├── layout.tsx        ✅ Uses ../opswap/providers.tsx
│   ├── components/       ✅ Clean action components
│   └── hooks/            ✅ Transaction and data hooks
└── opswap/               ⚠️ DEPRECATED (except providers.tsx)
    ├── providers.tsx     ✅ ONLY FILE USED (by mint/layout.tsx)
    └── [everything else] ❌ UNUSED OLD PROTOTYPE
```

## Routing

- `/` → Landing page with button to mint
- `/mint` → Active application
- `/opswap` → **NOT LINKED** anywhere (404 or shows old demo)

## Recommendation

**Keep this entire directory as-is:**

1. ✅ Keep: `providers.tsx` (actively used by mint/layout.tsx)
2. ✅ Keep: All other files (original prototype for reference)
3. 📝 Note: This is the OG (original) implementation

## Why It Exists

This is the **original prototype** of the options interface before the clean architecture refactor.

**Keep it for:**

- Historical reference
- Original implementation patterns
- Comparison with new clean architecture
- Potential feature ideas from the original design
