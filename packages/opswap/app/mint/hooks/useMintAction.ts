import { useCallback, useState } from "react";
import { Address, parseUnits } from "viem";
import { useWriteContract, useWaitForTransactionReceipt } from "wagmi";
import { useOptionContract } from "./useContracts";

interface UseMintActionReturn {
  /** Execute the mint transaction (assumes approvals are already done) */
  mint: (optionAddress: Address, amountWei: bigint) => Promise<`0x${string}` | null>;
  /** Whether mint transaction is pending */
  isPending: boolean;
  /** Transaction hash */
  txHash: `0x${string}` | null;
  /** Whether transaction was confirmed */
  isConfirmed: boolean;
  /** Whether transaction failed */
  isError: boolean;
  /** Error if any */
  error: Error | null;
}

/**
 * Simple hook to execute mint transaction
 * Does NOT handle approvals - that's the application's responsibility
 *
 * Usage:
 * 1. Application checks allowances
 * 2. Application handles approvals
 * 3. Application calls mint() when ready
 */
export function useMintAction(): UseMintActionReturn {
  const [txHash, setTxHash] = useState<`0x${string}` | null>(null);
  const [error, setError] = useState<Error | null>(null);

  const optionContract = useOptionContract();
  const { writeContractAsync, isPending } = useWriteContract();

  const { isSuccess: isConfirmed, isError } = useWaitForTransactionReceipt({
    hash: txHash ?? undefined,
  });

  const mint = useCallback(
    async (optionAddress: Address, amountWei: bigint): Promise<`0x${string}` | null> => {
      if (!optionContract?.abi) {
        const err = new Error("Option contract not available");
        setError(err);
        throw err;
      }

      try {
        setError(null);
        const hash = await writeContractAsync({
          address: optionAddress,
          abi: optionContract.abi as readonly unknown[],
          functionName: "mint",
          args: [amountWei],
        });
        setTxHash(hash);
        return hash;
      } catch (err) {
        setError(err as Error);
        throw err;
      }
    },
    [optionContract, writeContractAsync]
  );

  return {
    mint,
    isPending,
    txHash,
    isConfirmed,
    isError,
    error,
  };
}

export default useMintAction;
