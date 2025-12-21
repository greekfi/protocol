import { useCallback, useEffect, useState } from "react";
import { Address, parseUnits } from "viem";
import { useWriteContract, useWaitForTransactionReceipt } from "wagmi";
import { useOption } from "./useOption";
import { useApproval } from "./useApproval";
import { useOptionContract } from "./useContracts";
import type { TransactionStep } from "./types";

type MintStep = TransactionStep;

interface UseMintReturn {
  /** Execute mint with the given amount (human readable, e.g., "1.5") */
  mint: (amount: string) => Promise<void>;
  /** Current step in the mint flow */
  step: MintStep;
  /** Whether mint is in progress */
  isLoading: boolean;
  /** Whether mint succeeded */
  isSuccess: boolean;
  /** Error if any */
  error: Error | null;
  /** Transaction hash of the mint (not approvals) */
  txHash: `0x${string}` | null;
  /** Reset state */
  reset: () => void;
  /** The collateral amount in wei that will be minted */
  amountWei: bigint;
}

/**
 * Hook to mint options with automatic approval handling
 *
 * Flow:
 * 1. Check/request approvals for collateral token (two-layer: ERC20 + factory)
 * 2. Wait for approvals to confirm
 * 3. Call option.mint(amount)
 * 4. Wait for mint confirmation
 */
export function useMint(optionAddress: Address | undefined): UseMintReturn {
  const [step, setStep] = useState<MintStep>("idle");
  const [error, setError] = useState<Error | null>(null);
  const [txHash, setTxHash] = useState<`0x${string}` | null>(null);
  const [amountWei, setAmountWei] = useState<bigint>(0n);
  const [shouldExecuteMint, setShouldExecuteMint] = useState(false);

  const { data: option, refetch: refetchOption } = useOption(optionAddress);
  const optionContract = useOptionContract();

  const collateralAddress = option?.collateral.address;
  const collateralDecimals = option?.collateral.decimals ?? 18;

  const { writeContractAsync } = useWriteContract();

  // Approval hook - handles two-layer approval flow
  const {
    approve,
    step: approvalStep,
    isFullyApproved,
    error: approvalError,
    reset: resetApproval,
  } = useApproval({
    tokenAddress: collateralAddress,
    requiredAmount: amountWei,
    onApprovalComplete: () => {
      // Approvals done, trigger mint
      setShouldExecuteMint(true);
    },
    onError: (err) => {
      setError(err);
      setStep("error");
    },
  });

  // Wait for mint transaction
  const { isSuccess: mintConfirmed, isError: mintFailed, error: mintError } = useWaitForTransactionReceipt({
    hash: txHash ?? undefined,
    query: {
      enabled: Boolean(txHash) && step === "waiting-execution",
    },
  });

  // Handle mint confirmation
  useEffect(() => {
    if (mintConfirmed && step === "waiting-execution") {
      setStep("success");
      refetchOption();
    }
  }, [mintConfirmed, step, refetchOption]);

  // Handle mint failure
  useEffect(() => {
    if (mintFailed && mintError && step === "waiting-execution") {
      setError(mintError);
      setStep("error");
    }
  }, [mintFailed, mintError, step]);

  // Execute mint when approvals are complete
  useEffect(() => {
    if (!shouldExecuteMint) return;
    if (!optionAddress || !optionContract?.abi) return;

    const doMint = async () => {
      try {
        setShouldExecuteMint(false);
        setStep("executing");

        const hash = await writeContractAsync({
          address: optionAddress,
          abi: optionContract.abi as readonly unknown[],
          functionName: "mint",
          args: [amountWei],
        });

        setTxHash(hash);
        setStep("waiting-execution");
      } catch (err) {
        setError(err as Error);
        setStep("error");
      }
    };

    doMint();
  }, [shouldExecuteMint, optionAddress, optionContract?.abi, amountWei, writeContractAsync]);

  // Sync approval step to our step
  useEffect(() => {
    if (step === "idle" || step === "success" || step === "error") return;

    // Map approval steps to our steps
    if (approvalStep === "approving-erc20") setStep("approving-erc20");
    else if (approvalStep === "waiting-erc20") setStep("waiting-erc20");
    else if (approvalStep === "approving-factory") setStep("approving-factory");
    else if (approvalStep === "waiting-factory") setStep("waiting-factory");
  }, [approvalStep, step]);

  const mint = useCallback(
    async (amountStr: string) => {
      if (!optionAddress || !optionContract?.abi) {
        setError(new Error("Option not loaded"));
        setStep("error");
        return;
      }

      if (!collateralAddress) {
        setError(new Error("Collateral address not available"));
        setStep("error");
        return;
      }

      if (option?.isExpired) {
        setError(new Error("Option has expired"));
        setStep("error");
        return;
      }

      try {
        // Parse amount
        const wei = parseUnits(amountStr, collateralDecimals);
        if (wei <= 0n) {
          setError(new Error("Amount must be greater than 0"));
          setStep("error");
          return;
        }

        setAmountWei(wei);
        setError(null);
        setTxHash(null);
        setStep("checking-allowance");

        // If already approved, skip to mint
        if (isFullyApproved) {
          setShouldExecuteMint(true);
          return;
        }

        // Start approval flow
        await approve();
      } catch (err) {
        setError(err as Error);
        setStep("error");
      }
    },
    [optionAddress, optionContract?.abi, collateralAddress, collateralDecimals, option?.isExpired, isFullyApproved, approve]
  );

  const reset = useCallback(() => {
    setStep("idle");
    setError(null);
    setTxHash(null);
    setAmountWei(0n);
    setShouldExecuteMint(false);
    resetApproval();
  }, [resetApproval]);

  return {
    mint,
    step,
    isLoading: step !== "idle" && step !== "success" && step !== "error",
    isSuccess: step === "success",
    error: error ?? approvalError,
    txHash,
    reset,
    amountWei,
  };
}

export default useMint;
