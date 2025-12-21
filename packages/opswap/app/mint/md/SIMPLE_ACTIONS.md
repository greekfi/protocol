# Simple Action Components

All three main actions (Mint, Exercise, Redeem) now follow the same clean, simple pattern.

## Architecture

```
Transaction Hooks (Pure Writes)
├── useApproveERC20()      - Approve any ERC20 token
├── useApproveFactory()    - Approve factory for token
├── useMintTransaction()   - Execute mint
├── useExerciseTransaction() - Execute exercise
└── useRedeemTransaction() - Execute redeem

Data Hooks (Pure Reads)
├── useOption()           - Get option details + balances
├── useAllowances()       - Get allowance state
└── useOptions()          - Get all options list

Components (Contains Logic)
├── MintActionClean       - Mint options (deposit collateral)
├── ExerciseAction        - Exercise options (pay consideration, get collateral)
└── RedeemAction          - Redeem pairs (burn both tokens, get collateral)
```

## Pattern

Each component follows the same simple pattern:

```typescript
export function ActionComponent({ optionAddress }: Props) {
  // 1. Local state
  const [amount, setAmount] = useState("");
  const [txHash, setTxHash] = useState<`0x${string}` | null>(null);
  const [status, setStatus] = useState<"idle" | "working" | "success">("idle");

  // 2. Fetch data
  const { data: option } = useOption(optionAddress);
  const allowances = useAllowances(tokenAddress, amount);

  // 3. Get transaction executors
  const approveERC20 = useApproveERC20();
  const actionTx = useActionTransaction();

  // 4. Handle transaction confirmation
  const { isSuccess } = useWaitForTransactionReceipt({ hash: txHash });
  if (txHash && isSuccess) {
    // Move to next step or mark complete
  }

  // 5. Handle action button click
  const handleAction = async () => {
    // Check if approval needed
    if (allowances.needsErc20Approval) {
      await approveERC20.approve(token, spender);
      return; // Wait for confirmation
    }

    // Execute action
    await actionTx.execute(optionAddress, amount);
  };

  return <button onClick={handleAction}>Action</button>;
}
```

## Components

### 1. MintActionClean (Blue)
**What it does:** Deposits collateral to create Option + Redemption token pairs

**Steps:**
1. Approve collateral token → factory (if needed)
2. Approve factory → collateral token (if needed)
3. Mint

**Key data:**
- Collateral token balance
- Option token balance
- Redemption token balance

### 2. ExerciseAction (Green)
**What it does:** Burns Option tokens, pays consideration, receives collateral

**Steps:**
1. Approve consideration token → factory (if needed)
2. Exercise

**Key data:**
- Consideration token balance (what you pay)
- Option token balance (what you burn)
- Collateral balance (what you'll receive)

### 3. RedeemAction (Purple)
**What it does:** Burns matching Option + Redemption pairs to get collateral back

**Steps:**
1. Redeem (no approvals needed - you own both tokens)

**Key data:**
- Option token balance
- Redemption token balance
- Max redeemable = min(option, redemption)
- Collateral balance

## Example: Adding a New Action

To add a new action (e.g., "Sweep"):

1. **Create transaction hook** (`hooks/transactions/useSweepTransaction.ts`):
```typescript
export function useSweepTransaction() {
  const { writeContractAsync } = useWriteContract();
  const contract = useRedemptionContract();

  const sweep = async (redemptionAddress: Address, holders: Address[]) => {
    const hash = await writeContractAsync({
      address: redemptionAddress,
      abi: contract.abi,
      functionName: "sweep",
      args: [holders],
    });
    return hash;
  };

  return { sweep };
}
```

2. **Create component** (`components/SweepAction.tsx`):
```typescript
export function SweepAction({ optionAddress }: Props) {
  const [holders, setHolders] = useState<Address[]>([]);
  const [txHash, setTxHash] = useState<`0x${string}` | null>(null);

  const { data: option } = useOption(optionAddress);
  const sweepTx = useSweepTransaction();

  const handleSweep = async () => {
    const hash = await sweepTx.sweep(option.redemption, holders);
    setTxHash(hash);
  };

  return <button onClick={handleSweep}>Sweep</button>;
}
```

3. **Use in page**:
```typescript
import SweepAction from "./components/SweepAction";

<SweepAction optionAddress={optionAddress} />
```

## Benefits

1. **Easy to understand** - All logic visible in component
2. **Easy to modify** - Change component logic without touching hooks
3. **Easy to test** - Mock transaction hooks, test component logic
4. **Easy to debug** - Step through component code to see what's happening
5. **Easy to extend** - Add new actions following same pattern

## File Structure

```
app/mint/
├── components/
│   ├── MintActionClean.tsx      ✅ Blue - Mint options
│   ├── ExerciseAction.tsx       ✅ Green - Exercise options
│   └── RedeemAction.tsx         ✅ Purple - Redeem pairs
│
├── hooks/
│   ├── transactions/
│   │   ├── useApproveERC20.ts      ✅ ERC20 approval
│   │   ├── useApproveFactory.ts    ✅ Factory approval
│   │   ├── useMintTransaction.ts   ✅ Mint transaction
│   │   ├── useExerciseTransaction.ts ✅ Exercise transaction
│   │   └── useRedeemTransaction.ts ✅ Redeem transaction
│   │
│   ├── useOption.ts              ✅ Read option data
│   ├── useOptions.ts             ✅ Read options list
│   ├── useAllowances.ts          ✅ Read allowance data
│   └── useContracts.ts           ✅ Get contract instances
│
└── page.tsx                      ✅ Uses all three clean components
```

## What's Different From Before

**Before:**
- Complex hooks with state machines
- Logic hidden inside hooks
- Hard to understand flow
- Hard to modify behavior

**After:**
- Simple transaction executors
- Logic visible in components
- Clear, explicit flow
- Easy to modify behavior

**Example - Before:**
```typescript
// What does this do? 🤷
const { mint } = useMintWithApprovals(address);
await mint(amount);
// Magic happens...
```

**Example - After:**
```typescript
// Clear and explicit 👍
const approveERC20 = useApproveERC20();
const mint = useMintTransaction();

if (needsApproval) {
  await approveERC20.approve(token, factory);
}
await mint.mint(address, amount);
```
