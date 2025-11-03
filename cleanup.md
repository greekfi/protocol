# Unused Code Analysis Report

Generated: 2025-11-03

I've analyzed your codebase using **knip** and **depcheck**. Here's what can be safely removed:

---

## **1. Unused Files (26 files - Safe to Delete)**

These files are not imported or used anywhere:

### Duplicate/Old files:
- `app/mint/App copy.css`
- `app/mint/index copy.css`

### Unused CSS files:
- `app/mint/App.css`
- `app/mint/index.css`

### Unused components:
- `app/mint/Balance.tsx`
- `app/mint/components/OptionInterface.tsx`
- `app/mint/components/TokenBalance.tsx`
- `app/mint/contractInfo.tsx`
- `app/mint/Create.tsx`
- `app/shared/components/TokenBalance.tsx`
- `app/shared/components/TooltipButton.tsx`
- `app/shared/components/walletSelector.tsx`

### Unused hooks:
- `app/mint/hooks/permit2abi.ts`
- `app/mint/hooks/useGetDetails.ts` *(currently open in your IDE)*
- `app/mint/hooks/usePermit2.ts`
- `app/shared/hooks/permit2abi.ts`
- `app/shared/hooks/useAllowanceCheck.ts`
- `app/shared/hooks/useContract.ts`
- `app/shared/hooks/useGetOptions.ts`
- `app/shared/hooks/useGetOptionsByPair.ts`
- `app/shared/hooks/usePermit2.ts`

### Unused config:
- `app/chains/unichain.ts`

### Unused Scaffold-ETH components:
- `components/assets/BuidlGuidlLogo.tsx`
- `components/Footer.tsx`
- `components/Header.tsx`
- `components/SwitchTheme.tsx`

---

## **2. Unused Dependencies (Can be removed)**

### Regular dependencies:
- `daisyui` - Tailwind UI library not being used
- `kubo-rpc-client` - IPFS client not being used

### Dev dependencies:
- `@swc/cli` - SWC compiler CLI not used
- `@swc/core` - SWC compiler core not used
- `autoprefixer` - PostCSS plugin (likely replaced by Tailwind v4)
- `eslint-config-next` - Not referenced in eslint config

**Note:** depcheck incorrectly flagged these as unused (they ARE needed):
- `@tailwindcss/postcss` - Required for Tailwind v4
- `postcss` - Required for Tailwind v4
- `tailwindcss` - Obviously needed

---

## **3. Missing Dependencies (Should be added)**

These are used but not in package.json:

- `moment-timezone` - Used in `app/mint/Create.tsx:5` and `app/mint/CreateMany.tsx:5`
  - **Action:** Move from root package.json to nextjs package.json

- `@eslint/eslintrc` - Used in `eslint.config.mjs:1`
  - **Action:** Add to devDependencies

---

## **4. Unused Exports (Low priority - internal APIs)**

These are exported but not used elsewhere (19 exports + 8 types + 63 enum members). Most are Scaffold-ETH utilities that you might use later:

### High-value potential removals:
- `localhost`, `availableChains`, `useChainStore` in `app/mint/config.ts` - if truly unused
- Default export in `app/mint/hooks/useGetOption.ts:67`

### Keep for now (Scaffold-ETH utilities):
- `useScaffoldContract`, `useScaffoldReadContract`, etc. - These are framework features you might use
- `IntegerVariant` enum members - Part of the input validation system

---

## **Recommended Actions**

### Quick wins (safe deletions):

```bash
# Navigate to nextjs directory
cd packages/nextjs

# Remove duplicate/old files
rm "app/mint/App copy.css" "app/mint/index copy.css"

# Remove unused CSS
rm app/mint/App.css app/mint/index.css

# Remove unused components and hooks
rm -rf app/mint/components
rm app/mint/Create.tsx app/mint/Balance.tsx app/mint/contractInfo.tsx
rm -rf app/shared/components app/shared/hooks

# Remove unused mint hooks
rm app/mint/hooks/permit2abi.ts app/mint/hooks/useGetDetails.ts app/mint/hooks/usePermit2.ts

# Remove unused config
rm app/chains/unichain.ts

# Remove unused Scaffold-ETH components
rm components/Footer.tsx components/Header.tsx components/SwitchTheme.tsx
rm -rf components/assets
```

### Clean up dependencies in package.json:

```bash
# Navigate to nextjs directory
cd packages/nextjs

# Remove unused dependencies
yarn remove daisyui kubo-rpc-client @swc/cli @swc/core autoprefixer eslint-config-next

# Add missing dev dependency
yarn add -D @eslint/eslintrc
```

### Fix missing dependency:

Since `moment-timezone` is already in the root package.json, no action needed unless you want to move it to the nextjs package specifically.

---

## **Cleanup Verification**

After running the cleanup, verify everything still works:

```bash
# Compile TypeScript
yarn next:check-types

# Run linters
yarn next:lint

# Build the project
yarn next:build

# Run the dev server
yarn start
```

---

## **Tools Used**

- **knip** (v5.67.1) - Comprehensive unused code detection
- **depcheck** (v1.4.7) - Unused dependency detection

### Re-run analysis:

```bash
cd packages/nextjs
npx knip                    # Find unused files, exports, dependencies
npx depcheck                # Find unused dependencies (second opinion)
```

---

## **Estimated Impact**

- **Files removed:** 26 files (~several KB of unused code)
- **Dependencies removed:** 6 packages (~reduced node_modules size)
- **Maintenance burden:** Reduced surface area for future refactoring
- **Build performance:** Slightly faster due to fewer files to process
