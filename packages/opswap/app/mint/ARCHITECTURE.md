# Mint Flow Architecture

## Overview

The mint flow has been refactored to follow a **separation of concerns** principle where:
1. **State lives at the application level** (in hooks or page components)
2. **Components are purely presentational** (receive all state as props)
3. **Hooks are single-purpose** (do one thing well)

## Architecture Diagram

```
┌─────────────────────────────────────────────────────┐
│                    page.tsx                         │
│  ┌────────────────────────────────────────────┐    │
│  │         useMintFlow(optionAddress)         │    │
│  │  - Manages entire mint flow state          │    │
│  │  - Orchestrates all steps                  │    │
│  │  - Returns MintFlowData                    │    │
│  └────────────────────────────────────────────┘    │
│                       │                             │
│                       ↓                             │
│  ┌────────────────────────────────────────────┐    │
│  │    <MintActionPresentational />            │    │
│  │  - Purely presentational                   │    │
│  │  - Receives mintFlow + option as props     │    │
│  │  - Renders UI based on state               │    │
│  └────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────┘

                Internal to useMintFlow:
        ┌─────────────────────────────────┐
        │      useAllowances()            │
        │  - Checks current allowances    │
        │  - Returns approval needs       │
        └─────────────────────────────────┘
                       │
                       ↓
        ┌─────────────────────────────────┐
        │       useApprove()              │
        │  - Executes approval txs        │
        │  - Returns tx hashes            │
        └─────────────────────────────────┘
                       │
                       ↓
        ┌─────────────────────────────────┐
        │      useMintAction()            │
        │  - Executes mint tx             │
        │  - Returns tx hash              │
        └─────────────────────────────────┘
```

## State Flow

### State Lives in `useMintFlow`

```typescript
const mintFlow = useMintFlow(optionAddress);
// mintFlow contains:
// - state: Current flow state (idle, checking, needs-approval, etc.)
// - error: Any error that occurred
// - amount: Human-readable amount
// - amountWei: Amount in wei
// - erc20Allowance: Current ERC20 allowance
// - factoryAllowance: Current factory allowance
// - needsErc20Approval: Whether ERC20 approval is needed
// - needsFactoryApproval: Whether factory approval is needed
// - isFullyApproved: Whether all approvals are satisfied
// - Transaction hashes for all steps
// - Actions: setAmount, startMintFlow, executeCurrentStep, reset
```

### Component Receives State

```typescript
<MintActionPresentational
  option={optionDetails}
  mintFlow={mintFlow}
/>
// Component is purely presentational:
// - Displays current state
// - Shows approval status
// - Renders button based on state
// - Calls mintFlow actions on user interaction
```

## Flow States

The mint flow progresses through these states:

1. **idle** - Initial state, user hasn't started
2. **input** - User is entering amount (optional state)
3. **checking-allowances** - Checking what approvals are needed
4. **needs-erc20-approval** - Need to approve ERC20 token to factory
5. **approving-erc20** - User confirming ERC20 approval in wallet
6. **waiting-erc20** - Waiting for ERC20 approval confirmation on-chain
7. **needs-factory-approval** - Need to approve factory for token
8. **approving-factory** - User confirming factory approval in wallet
9. **waiting-factory** - Waiting for factory approval confirmation on-chain
10. **ready-to-mint** - All approvals done, ready to mint
11. **minting** - User confirming mint in wallet
12. **waiting-mint** - Waiting for mint confirmation on-chain
13. **success** - Mint completed successfully
14. **error** - Error occurred at any step

## Key Hooks

### `useAllowances(tokenAddress, requiredAmount)`

**Purpose**: Check current allowance state

**Returns**:
- `erc20Allowance`: Current ERC20 allowance
- `factoryAllowance`: Current factory allowance
- `needsErc20Approval`: boolean
- `needsFactoryApproval`: boolean
- `isFullyApproved`: boolean
- `refetch()`: Function to refresh allowances

**Does NOT**:
- Execute any transactions
- Manage any state beyond what it queries

### `useApprove()`

**Purpose**: Execute approval transactions

**Returns**:
- `approveErc20(tokenAddress)`: Approve ERC20 to factory
- `approveFactory(tokenAddress)`: Approve factory for token
- `isPending`: Whether a transaction is pending
- `txHash`: Last transaction hash
- `error`: Any error

**Does NOT**:
- Check allowances (that's useAllowances' job)
- Decide which approvals are needed
- Manage flow state

### `useMintAction()`

**Purpose**: Execute mint transaction

**Returns**:
- `mint(optionAddress, amountWei)`: Execute mint
- `isPending`: Whether mint is pending
- `txHash`: Mint transaction hash
- `isConfirmed`: Whether mint was confirmed
- `isError`: Whether mint failed
- `error`: Any error

**Does NOT**:
- Handle approvals
- Manage flow state

### `useMintFlow(optionAddress)`

**Purpose**: Orchestrate the entire mint flow

**Returns**: `MintFlowData` with:
- All state
- All allowance data
- All transaction hashes
- Actions to control the flow

**Responsibilities**:
- Manages the state machine
- Calls other hooks internally
- Provides actions to components
- Handles state transitions based on tx confirmations

## Benefits of This Architecture

### 1. **Separation of Concerns**
- Each hook does ONE thing
- Components don't manage state
- State lives in one place

### 2. **Testability**
- Each hook can be tested independently
- Components can be tested with mock state
- State transitions are predictable

### 3. **Reusability**
- `useAllowances` can be used anywhere (exercise, redeem, etc.)
- `useApprove` can be used for any token approval flow
- `useMintAction` is a simple transaction executor

### 4. **Visibility**
- Application can see allowance state at any time
- Application decides what to show to user
- Debugging is easier (all state in one place)

### 5. **Flexibility**
- Easy to add new steps to the flow
- Easy to change flow logic
- Easy to customize UI based on state

## Example: Adding a New Action (Exercise)

```typescript
// 1. Create simple transaction hook
export function useExerciseAction() {
  const { writeContractAsync } = useWriteContract();
  const exercise = async (optionAddress, amount) => {
    const hash = await writeContractAsync({
      address: optionAddress,
      functionName: "exercise",
      args: [amount],
    });
    return hash;
  };
  return { exercise };
}

// 2. Create flow hook (similar to useMintFlow)
export function useExerciseFlow(optionAddress) {
  const [state, setState] = useState("idle");
  // Use useAllowances for consideration token
  const allowances = useAllowances(considerationAddress, amount);
  // Use useApprove for approvals
  const { approveErc20, approveFactory } = useApprove();
  // Use useExerciseAction for the action
  const { exercise } = useExerciseAction();

  // Orchestrate the flow...
  return { state, allowances, actions };
}

// 3. Create presentational component
export function ExerciseActionPresentational({ option, exerciseFlow }) {
  // Render based on exerciseFlow.state
  // Call exerciseFlow.actions on user interaction
}

// 4. Wire up in page.tsx
const exerciseFlow = useExerciseFlow(optionAddress);
<ExerciseActionPresentational option={option} exerciseFlow={exerciseFlow} />
```

## Migration Path

Old code can coexist with new code:
- Keep old `useMint` hook for backward compatibility
- New code uses `useMintFlow` + presentational components
- Gradually migrate other actions (exercise, redeem) to new pattern

## Files

### New Architecture Files
- `hooks/useAllowances.ts` - Check allowances (already existed, no changes)
- `hooks/useApprove.ts` - Execute approval transactions (NEW)
- `hooks/useMintAction.ts` - Execute mint transaction (NEW)
- `hooks/useMintFlow.ts` - Orchestrate mint flow (NEW)
- `components/MintActionPresentational.tsx` - Presentational mint UI (NEW)

### Old Files (can be deprecated)
- `hooks/useApproval.ts` - Tightly coupled approval flow
- `hooks/useMint.ts` - Tightly coupled mint flow
- `components/MintAction.tsx` - Stateful mint component

## Key Principles

1. **Hooks check, components decide, hooks execute**
2. **State flows down, actions flow up**
3. **One source of truth for each piece of state**
4. **Components don't know about transactions, just state**
5. **Hooks don't know about UI, just transactions**
