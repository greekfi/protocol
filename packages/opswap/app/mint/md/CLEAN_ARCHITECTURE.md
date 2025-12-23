# Clean Architecture - Separation of Concerns

This document explains the new simplified architecture where data fetching and transaction execution are completely separate from logic.

## Design Principles

1. **Hooks are ONLY for data or transactions** - no logic, no state machines
2. **Components contain all the logic** - they decide what to do and when
3. **Everything is simple and explicit** - no hidden flows or auto-magic

## Structure

```
hooks/
├── transactions/          # Pure transaction executors (write operations)
│   ├── useApproveERC20.ts       # ERC20 token approval
│   ├── useApproveFactory.ts     # Factory approval
│   ├── useMintTransaction.ts    # Mint transaction
│   ├── useExerciseTransaction.ts # Exercise transaction
│   └── useRedeemTransaction.ts  # Redeem transaction
│
├── useOption.ts          # Read single option data
├── useOptions.ts         # Read all options list
├── useAllowances.ts      # Read allowance data
└── useContracts.ts       # Get contract instances

components/
└── MintActionClean.tsx   # Contains ALL logic for minting
```

## How It Works

### Transaction Hooks (Pure Write Operations)

Each transaction hook does ONE thing only:

```typescript
// hooks/transactions/useApproveERC20.ts
export function useApproveERC20() {
  const { writeContractAsync, isPending, error } = useWriteContract();

  const approve = async (tokenAddress: Address, spenderAddress: Address) => {
    const hash = await writeContractAsync({
      address: tokenAddress,
      abi: erc20Abi,
      functionName: "approve",
      args: [spenderAddress, MAX_UINT256],
    });
    return hash;
  };

  return { approve, isPending, error };
}
```

**Key points:**
- Just wraps `writeContractAsync`
- Returns transaction hash
- No state management
- No decision making

### Data Hooks (Pure Read Operations)

Already exist and work well:
- `useOption(address)` - fetches option details
- `useAllowances(token, amount)` - fetches allowance state
- `useOptions()` - fetches list of options

### Component Logic (Where Everything Happens)

```typescript
// components/MintActionClean.tsx
export function MintActionClean({ optionAddress }: Props) {
  // Local component state
  const [amount, setAmount] = useState("");
  const [txHash, setTxHash] = useState<`0x${string}` | null>(null);
  const [status, setStatus] = useState<"idle" | "working" | "success">("idle");

  // Get data
  const { data: option } = useOption(optionAddress);
  const allowances = useAllowances(option?.collateral.address, amountWei);

  // Get transaction executors
  const approveERC20 = useApproveERC20();
  const approveFactory = useApproveFactory();
  const mintTx = useMintTransaction();

  // Wait for transaction
  const { isSuccess } = useWaitForTransactionReceipt({ hash: txHash });

  // Handle mint button click
  const handleMint = async () => {
    setStatus("working");

    // Step 1: Check if ERC20 approval needed
    if (allowances.needsErc20Approval) {
      const hash = await approveERC20.approve(tokenAddress, factoryAddress);
      setTxHash(hash);
      return; // Wait for confirmation
    }

    // Step 2: Check if factory approval needed
    if (allowances.needsFactoryApproval) {
      const hash = await approveFactory.approve(tokenAddress);
      setTxHash(hash);
      return; // Wait for confirmation
    }

    // Step 3: Mint
    const hash = await mintTx.mint(optionAddress, amount);
    setTxHash(hash);
  };

  // When transaction confirms, continue or finish
  if (txHash && isSuccess) {
    setTxHash(null);
    if (status === "working") {
      // If still working, call handleMint again to check next step
      handleMint();
    }
  }

  return (
    <button onClick={handleMint}>Mint</button>
  );
}
```

**Key points:**
- Component decides when to approve, when to mint
- Component tracks transaction state
- Component handles transaction confirmation
- All logic is visible and explicit

## Available Transaction Hooks

### `useApproveERC20()`
```typescript
const { approve, isPending, error } = useApproveERC20();
await approve(tokenAddress, spenderAddress);
```

### `useApproveFactory()`
```typescript
const { approve, isPending, error } = useApproveFactory();
await approve(tokenAddress);
```

### `useMintTransaction()`
```typescript
const { mint, isPending, error } = useMintTransaction();
await mint(optionAddress, amountWei);
```

### `useExerciseTransaction()`
```typescript
const { exercise, isPending, error } = useExerciseTransaction();
await exercise(optionAddress, amountWei);
```

### `useRedeemTransaction()`
```typescript
const { redeem, isPending, error } = useRedeemTransaction();
await redeem(optionAddress, amountWei);
```

## Benefits

1. **Simple** - Each hook does one thing
2. **Explicit** - All logic is visible in the component
3. **Testable** - Easy to test components and hooks separately
4. **Flexible** - Easy to change logic without touching hooks
5. **Debuggable** - Can see exactly what's happening

## Migration Path

Old complex hooks → New simple architecture:
- ❌ `useMintWithApprovals()` - complex auto-flow logic
- ✅ `useApproveERC20()` + `useApproveFactory()` + `useMintTransaction()` - simple, explicit

Old components → New clean components:
- ❌ `MintActionSimple.tsx` - uses complex hook
- ✅ `MintActionClean.tsx` - contains logic, uses simple hooks

## Example: Exercise Action

To create an Exercise component, you would:

```typescript
export function ExerciseAction({ optionAddress }: Props) {
  const [amount, setAmount] = useState("");
  const [txHash, setTxHash] = useState<`0x${string}` | null>(null);

  // Data
  const { data: option } = useOption(optionAddress);
  const allowances = useAllowances(option?.consideration.address, amountWei);

  // Transactions
  const approveERC20 = useApproveERC20();
  const exerciseTx = useExerciseTransaction();

  const handleExercise = async () => {
    // Check if approval needed for consideration token
    if (allowances.needsErc20Approval) {
      await approveERC20.approve(considerationToken, factoryAddress);
      return;
    }

    // Exercise
    await exerciseTx.exercise(optionAddress, amountWei);
  };

  return <button onClick={handleExercise}>Exercise</button>;
}
```

## No More Hidden Magic

Before:
```typescript
// User clicks button
// ??? Magic happens inside hook ???
// Eventually succeeds or fails
```

After:
```typescript
// User clicks button
// Component checks allowances
// Component approves if needed
// Component mints
// All logic visible in component
```
