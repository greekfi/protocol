import { useCallback, useEffect, useState } from "react";
import { Address, erc20Abi } from "viem";
import { useWriteContract, useWaitForTransactionReceipt } from "wagmi";
import { useAllowances } from "./useAllowances";
import { useFactoryAddress, useOptionFactoryContract } from "./useContracts";
import { MAX_UINT256 } from "./constants";
import type { TransactionStep } from "./types";

type ApprovalStep = Extract<
  TransactionStep,
  "idle" | "checking-allowance" | "approving-erc20" | "waiting-erc20" | "approving-factory" | "waiting-factory" | "error"
> | "approved";

interface UseApprovalOptions {
  /** Token to approve */
  tokenAddress: Address | undefined;
  /** Amount needed (used to check if approval is sufficient) */
  requiredAmount: bigint;
  /** Callback when both approvals are complete */
  onApprovalComplete?: () => void;
  /** Callback on error */
  onError?: (error: Error) => void;
}

interface UseApprovalReturn {
  /** Trigger the approval flow */
  approve: () => Promise<void>;
  /** Current step in the approval process */
  step: ApprovalStep;
  /** Whether approvals are in progress */
  isLoading: boolean;
  /** Error if any occurred */
  error: Error | null;
  /** Whether both approvals are already satisfied */
  isFullyApproved: boolean;
  /** Whether ERC20 approval is needed */
  needsErc20Approval: boolean;
  /** Whether factory approval is needed */
  needsFactoryApproval: boolean;
  /** Reset the approval state */
  reset: () => void;
  /** Last transaction hash */
  txHash: `0x${string}` | null;
}

/**
 * Hook to handle the two-layer approval flow for the OptionFactory
 *
 * Flow:
 * 1. Check current allowances
 * 2. If ERC20 approval needed: token.approve(factory, MAX) and wait
 * 3. If factory approval needed: factory.approve(token, MAX) and wait
 * 4. Call onApprovalComplete when done
 */
export function useApproval({
  tokenAddress,
  requiredAmount,
  onApprovalComplete,
  onError,
}: UseApprovalOptions): UseApprovalReturn {
  const [step, setStep] = useState<ApprovalStep>("idle");
  const [error, setError] = useState<Error | null>(null);
  const [pendingHash, setPendingHash] = useState<`0x${string}` | null>(null);
  const [txHash, setTxHash] = useState<`0x${string}` | null>(null);

  const factoryAddress = useFactoryAddress();
  const factoryContract = useOptionFactoryContract();

  const { needsErc20Approval, needsFactoryApproval, isFullyApproved, refetch: refetchAllowances } = useAllowances(
    tokenAddress,
    requiredAmount
  );

  const { writeContractAsync } = useWriteContract();

  // Wait for transaction receipt
  const { isSuccess: txConfirmed, isError: txFailed, error: txError } = useWaitForTransactionReceipt({
    hash: pendingHash ?? undefined,
    query: {
      enabled: Boolean(pendingHash),
    },
  });

  // Handle transaction confirmation - move to next step
  useEffect(() => {
    if (!pendingHash || !txConfirmed) return;

    setTxHash(pendingHash);
    setPendingHash(null);

    if (step === "waiting-erc20") {
      // ERC20 approval confirmed, check if factory approval needed
      refetchAllowances();
      if (needsFactoryApproval) {
        setStep("approving-factory");
      } else {
        setStep("approved");
        onApprovalComplete?.();
      }
    } else if (step === "waiting-factory") {
      // Factory approval confirmed
      refetchAllowances();
      setStep("approved");
      onApprovalComplete?.();
    }
  }, [pendingHash, txConfirmed, step, needsFactoryApproval, refetchAllowances, onApprovalComplete]);

  // Handle transaction failure
  useEffect(() => {
    if (pendingHash && txFailed && txError) {
      setError(txError);
      setStep("error");
      setPendingHash(null);
      onError?.(txError);
    }
  }, [pendingHash, txFailed, txError, onError]);

  // Execute factory approval when step changes to approving-factory
  useEffect(() => {
    if (step !== "approving-factory") return;
    if (!factoryAddress || !factoryContract?.abi || !tokenAddress) return;

    const doFactoryApproval = async () => {
      try {
        const hash = await writeContractAsync({
          address: factoryAddress,
          abi: factoryContract.abi as readonly unknown[],
          functionName: "approve",
          args: [tokenAddress, MAX_UINT256],
        });
        setPendingHash(hash);
        setStep("waiting-factory");
      } catch (err) {
        setError(err as Error);
        setStep("error");
        onError?.(err as Error);
      }
    };

    doFactoryApproval();
  }, [step, factoryAddress, factoryContract?.abi, tokenAddress, writeContractAsync, onError]);

  const approve = useCallback(async () => {
    if (!tokenAddress || !factoryAddress || !factoryContract?.abi) {
      const err = new Error("Missing token or factory address");
      setError(err);
      setStep("error");
      onError?.(err);
      return;
    }

    // If already approved, skip
    if (isFullyApproved) {
      setStep("approved");
      onApprovalComplete?.();
      return;
    }

    try {
      setError(null);
      setStep("checking-allowance");

      // Refetch to get latest allowances
      await refetchAllowances();

      // Step 1: ERC20 approval if needed
      if (needsErc20Approval) {
        setStep("approving-erc20");
        const hash = await writeContractAsync({
          address: tokenAddress,
          abi: erc20Abi,
          functionName: "approve",
          args: [factoryAddress, MAX_UINT256],
        });
        setPendingHash(hash);
        setStep("waiting-erc20");
        // The useEffect will handle the next step when tx confirms
        return;
      }

      // Step 2: Factory approval if needed (and ERC20 was already approved)
      if (needsFactoryApproval) {
        setStep("approving-factory");
        // The useEffect will handle the approval
        return;
      }

      // Both already approved
      setStep("approved");
      onApprovalComplete?.();
    } catch (err) {
      setError(err as Error);
      setStep("error");
      onError?.(err as Error);
    }
  }, [
    tokenAddress,
    factoryAddress,
    factoryContract?.abi,
    isFullyApproved,
    needsErc20Approval,
    needsFactoryApproval,
    refetchAllowances,
    writeContractAsync,
    onApprovalComplete,
    onError,
  ]);

  const reset = useCallback(() => {
    setStep("idle");
    setError(null);
    setPendingHash(null);
    setTxHash(null);
  }, []);

  const isLoading = step !== "idle" && step !== "approved" && step !== "error";

  return {
    approve,
    step,
    isLoading,
    error,
    isFullyApproved,
    needsErc20Approval,
    needsFactoryApproval,
    reset,
    txHash,
  };
}

export default useApproval;
