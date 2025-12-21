# File Reorganization Plan

## Issues with Current Structure

1. **CSS files in mint/** - Should be in styles or at root
2. **JSON files in mint/** - Should be in data or config
3. **Components at root of mint/** - Should be in components/
4. **Unused CSS files** - App.css, index.css, etc. (unused copies)

## Current Structure (Messy)

```
app/mint/
├── page.tsx                 ✅ Keep (page route)
├── layout.tsx               ✅ Keep (layout route)
├── Navbar.tsx               ❌ Move to components/
├── Details.tsx              ❌ Move to components/
├── Selector.tsx             ❌ Move to components/
├── CreateMany.tsx           ❌ Move to components/
├── account.tsx              ⚠️ UNUSED (already marked)
├── action.tsx               ⚠️ UNUSED (already marked)
├── contractInfo.tsx         ⚠️ UNUSED (already marked)
├── Balance.tsx              ⚠️ UNUSED (already marked)
├── config.ts                ⚠️ UNUSED (already marked)
├── tokenList.json           ❌ Move to data/ or config/
├── tokenListLocal.json      ❌ Move to data/ or config/
├── App.css                  ⚠️ DELETE (unused copy)
├── App copy.css             ⚠️ DELETE (unused copy)
├── index.css                ⚠️ DELETE (unused)
├── index copy.css           ⚠️ DELETE (unused copy)
├── components/              ✅ Good
├── hooks/                   ✅ Good
└── UNUSED_FILES.md          ✅ Good
```

## Proposed Structure (Clean)

```
app/mint/
├── page.tsx                           ✅ Page route
├── layout.tsx                         ✅ Layout route
├── components/
│   ├── Navbar.tsx                     ← Move from root
│   ├── ContractDetails.tsx            ← Rename from Details.tsx
│   ├── OptionSelector.tsx             ← Rename from Selector.tsx
│   ├── CreateMany.tsx                 ← Move from root
│   ├── DesignHeader.tsx               ✅ Already here
│   ├── TooltipButton.tsx              ✅ Already here
│   ├── TokenBalanceNow.tsx            ✅ Already here
│   ├── MintActionClean.tsx            ✅ Already here
│   ├── ExerciseAction.tsx             ✅ Already here
│   └── RedeemAction.tsx               ✅ Already here
├── hooks/
│   ├── transactions/                  ✅ Already organized
│   ├── types/                         ✅ Already organized
│   └── [all data hooks]               ✅ Already organized
├── data/
│   ├── tokenList.json                 ← Move from root
│   └── tokenListLocal.json            ← Move from root
└── [documentation files]              ✅ Keep

app/styles/ (or root level)
└── globals.css                        ✅ Already exists at correct location
```

## Files to Move

### 1. Components (mint/ → mint/components/)
- `Navbar.tsx` → `components/Navbar.tsx`
- `Details.tsx` → `components/ContractDetails.tsx` (rename for clarity)
- `Selector.tsx` → `components/OptionSelector.tsx` (rename for clarity)
- `CreateMany.tsx` → `components/CreateMany.tsx`

### 2. Data Files (mint/ → mint/data/)
- `tokenList.json` → `data/tokenList.json`
- `tokenListLocal.json` → `data/tokenListLocal.json`

### 3. Files to Delete (Unused)
- ⚠️ `App.css` - Unused
- ⚠️ `App copy.css` - Unused copy
- ⚠️ `index.css` - Unused
- ⚠️ `index copy.css` - Unused copy

## Import Updates Needed

### After moving Navbar, Details, Selector, CreateMany:

**page.tsx:**
```typescript
// Before
import CreateMany from "./CreateMany";
import ContractDetails from "./Details";
import Navbar from "./Navbar";
import SelectOptionAddress from "./Selector";

// After
import CreateMany from "./components/CreateMany";
import ContractDetails from "./components/ContractDetails";
import Navbar from "./components/Navbar";
import OptionSelector from "./components/OptionSelector";
```

### After moving tokenList.json:

**hooks/useTokenMap.ts:**
```typescript
// Before
import tokenList from "../tokenList.json";

// After
import tokenList from "../data/tokenList.json";
```

## Benefits

1. **Clearer Structure** - Components in components/, data in data/
2. **Better Names** - ContractDetails, OptionSelector (more descriptive)
3. **Cleaner Root** - Only page.tsx, layout.tsx at root
4. **No Unused CSS** - Delete duplicate/unused CSS files
5. **Standard Convention** - Follows Next.js best practices

## Implementation Steps

1. Create `data/` directory
2. Move JSON files to `data/`
3. Move component files to `components/`
4. Update imports in page.tsx
5. Update imports in useTokenMap.ts
6. Test that everything still works
7. Delete unused CSS files
8. Update documentation

## Note on CSS

The CSS files at the root (`App.css`, `index.css`, etc.) appear to be unused copies from an older structure. The application is using:
- `@rainbow-me/rainbowkit/styles.css` (from RainbowKit)
- `../../styles/globals.css` (from root styles directory)

These can be safely deleted.
