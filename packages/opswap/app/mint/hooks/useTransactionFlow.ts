import { useCallback, useEffect, useState } from "react";
import { useWaitForTransactionReceipt } from "wagmi";
import type { TransactionStep, TransactionFlowState } from "./types";

interface UseTransactionFlowOptions {
  onSuccess?: (txHash: `0x${string}`) => void;
  onError?: (error: Error) => void;
}

interface UseTransactionFlowReturn extends TransactionFlowState {
  /** Set the current step manually */
  setStep: (step: TransactionStep) => void;
  /** Set error and move to error state */
  setError: (error: Error) => void;
  /** Set a pending transaction hash to wait for */
  setPendingHash: (hash: `0x${string}`) => void;
  /** Reset the flow to idle state */
  reset: () => void;
  /** Whether currently waiting for a transaction */
  isWaitingForTx: boolean;
  /** The pending transaction hash being waited on */
  pendingHash: `0x${string}` | null;
}

/**
 * Hook to manage multi-step transaction flow state
 *
 * This provides a state machine for tracking transaction progress:
 * idle → checking → approving → waiting → executing → success/error
 *
 * @param options - Callbacks for success/error
 * @returns Transaction flow state and control functions
 */
export function useTransactionFlow(options: UseTransactionFlowOptions = {}): UseTransactionFlowReturn {
  const [step, setStepInternal] = useState<TransactionStep>("idle");
  const [error, setErrorInternal] = useState<Error | null>(null);
  const [txHash, setTxHash] = useState<`0x${string}` | null>(null);
  const [pendingHash, setPendingHashInternal] = useState<`0x${string}` | null>(null);

  // Wait for transaction receipt
  const {
    isLoading: isWaitingForTx,
    isSuccess: txConfirmed,
    isError: txFailed,
    error: txError,
  } = useWaitForTransactionReceipt({
    hash: pendingHash ?? undefined,
    query: {
      enabled: Boolean(pendingHash),
    },
  });

  // Handle transaction confirmation
  useEffect(() => {
    if (pendingHash && txConfirmed) {
      setTxHash(pendingHash);
      setPendingHashInternal(null);
      // Don't auto-set success here - let the calling hook decide
    }
  }, [pendingHash, txConfirmed]);

  // Handle transaction failure
  useEffect(() => {
    if (pendingHash && txFailed && txError) {
      setErrorInternal(txError);
      setStepInternal("error");
      setPendingHashInternal(null);
      options.onError?.(txError);
    }
  }, [pendingHash, txFailed, txError, options]);

  const setStep = useCallback((newStep: TransactionStep) => {
    setStepInternal(newStep);
    if (newStep === "idle") {
      setErrorInternal(null);
      setTxHash(null);
      setPendingHashInternal(null);
    }
  }, []);

  const setError = useCallback(
    (err: Error) => {
      setErrorInternal(err);
      setStepInternal("error");
      options.onError?.(err);
    },
    [options]
  );

  const setPendingHash = useCallback((hash: `0x${string}`) => {
    setPendingHashInternal(hash);
    setTxHash(hash);
  }, []);

  const reset = useCallback(() => {
    setStepInternal("idle");
    setErrorInternal(null);
    setTxHash(null);
    setPendingHashInternal(null);
  }, []);

  const isLoading = step !== "idle" && step !== "success" && step !== "error";
  const isSuccess = step === "success";
  const isError = step === "error";

  return {
    step,
    error,
    txHash,
    isLoading,
    isSuccess,
    isError,
    setStep,
    setError,
    setPendingHash,
    reset,
    isWaitingForTx,
    pendingHash,
  };
}

/**
 * Helper to get a human-readable label for a transaction step
 */
export function getStepLabel(step: TransactionStep): string {
  switch (step) {
    case "idle":
      return "Ready";
    case "checking-allowance":
      return "Checking allowances...";
    case "approving-erc20":
      return "Approving token...";
    case "waiting-erc20":
      return "Confirming token approval...";
    case "approving-factory":
      return "Approving factory...";
    case "waiting-factory":
      return "Confirming factory approval...";
    case "executing":
      return "Executing...";
    case "waiting-execution":
      return "Confirming transaction...";
    case "success":
      return "Success!";
    case "error":
      return "Error";
    default:
      return step;
  }
}

/**
 * Get progress percentage for a step (0-100)
 */
export function getStepProgress(step: TransactionStep): number {
  const steps: TransactionStep[] = [
    "idle",
    "checking-allowance",
    "approving-erc20",
    "waiting-erc20",
    "approving-factory",
    "waiting-factory",
    "executing",
    "waiting-execution",
    "success",
  ];
  const index = steps.indexOf(step);
  if (index === -1) return 0;
  return Math.round((index / (steps.length - 1)) * 100);
}

export default useTransactionFlow;
