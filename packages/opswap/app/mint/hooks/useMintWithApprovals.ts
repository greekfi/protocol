import { useState, useCallback, useEffect } from "react";
import { Address, parseUnits } from "viem";
import { useWaitForTransactionReceipt } from "wagmi";
import { useAllowances } from "./useAllowances";
import { useApprove } from "./useApprove";
import { useMintAction } from "./useMintAction";
import { useOption } from "./useOption";

export type MintStatus =
  | "idle"
  | "checking"
  | "approving-erc20"
  | "approving-factory"
  | "minting"
  | "success"
  | "error";

export interface MintState {
  status: MintStatus;
  error: Error | null;
  txHash: `0x${string}` | null;

  // Allowance visibility
  erc20Allowance: bigint;
  factoryAllowance: bigint;
  needsErc20Approval: boolean;
  needsFactoryApproval: boolean;
}

/**
 * Simplified mint hook - just handles the mint action with auto-approvals
 *
 * When you call mint(), it:
 * 1. Checks allowances
 * 2. If needed, approves ERC20, waits for confirmation
 * 3. If needed, approves factory, waits for confirmation
 * 4. Mints
 *
 * All automatic - user just sees progress updates
 */
export function useMintWithApprovals(optionAddress: Address | undefined) {
  const [status, setStatus] = useState<MintStatus>("idle");
  const [error, setError] = useState<Error | null>(null);
  const [currentTxHash, setCurrentTxHash] = useState<`0x${string}` | null>(null);
  const [mintAmount, setMintAmount] = useState<bigint>(0n);

  const { data: option, refetch: refetchOption } = useOption(optionAddress);
  const collateralAddress = option?.collateral.address;
  const collateralDecimals = option?.collateral.decimals ?? 18;

  // Check allowances
  const allowances = useAllowances(collateralAddress, mintAmount);

  // Transaction executors
  const { approveErc20, approveFactory } = useApprove();
  const { mint: executeMint } = useMintAction();

  // Wait for current transaction
  const { isSuccess: txConfirmed, isError: txFailed } = useWaitForTransactionReceipt({
    hash: currentTxHash ?? undefined,
    query: {
      enabled: Boolean(currentTxHash),
    },
  });

  // Auto-progress through the flow
  const executeNextStep = useCallback(async () => {
    if (!collateralAddress || !optionAddress) return;

    try {
      // Refetch allowances to get latest state
      await allowances.refetch();

      // Check what needs to be done
      if (allowances.needsErc20Approval) {
        setStatus("approving-erc20");
        const hash = await approveErc20(collateralAddress);
        if (hash) {
          setCurrentTxHash(hash);
          // Will continue when txConfirmed updates
        }
      } else if (allowances.needsFactoryApproval) {
        setStatus("approving-factory");
        const hash = await approveFactory(collateralAddress);
        if (hash) {
          setCurrentTxHash(hash);
          // Will continue when txConfirmed updates
        }
      } else {
        // All approvals done, mint
        setStatus("minting");
        const hash = await executeMint(optionAddress, mintAmount);
        if (hash) {
          setCurrentTxHash(hash);
          // Will mark success when txConfirmed updates
        }
      }
    } catch (err) {
      setError(err as Error);
      setStatus("error");
    }
  }, [
    collateralAddress,
    optionAddress,
    mintAmount,
    allowances,
    approveErc20,
    approveFactory,
    executeMint,
  ]);

  // Handle transaction confirmation - move to next step
  useEffect(() => {
    if (!txConfirmed || status === "success" || status === "idle") return;

    if (status === "approving-erc20" || status === "approving-factory") {
      // Approval confirmed, check if more approvals needed
      allowances.refetch().then(() => {
        setCurrentTxHash(null); // Clear hash before next step
        executeNextStep();
      });
    } else if (status === "minting") {
      // Mint confirmed
      setStatus("success");
      setCurrentTxHash(null);
      refetchOption();
      allowances.refetch();
    }
  }, [txConfirmed, status, allowances, executeNextStep, refetchOption]);

  // Handle transaction failure
  useEffect(() => {
    if (txFailed && status !== "error") {
      setError(new Error("Transaction failed"));
      setStatus("error");
      setCurrentTxHash(null);
    }
  }, [txFailed, status]);

  /**
   * Main action - call this to mint with auto-approvals
   */
  const mint = useCallback(
    async (amount: string) => {
      if (!optionAddress || !collateralAddress) {
        setError(new Error("Option not loaded"));
        setStatus("error");
        return;
      }

      if (option?.isExpired) {
        setError(new Error("Option has expired"));
        setStatus("error");
        return;
      }

      try {
        const wei = parseUnits(amount, collateralDecimals);
        if (wei <= 0n) {
          setError(new Error("Amount must be greater than 0"));
          setStatus("error");
          return;
        }

        setError(null);
        setMintAmount(wei);
        setStatus("checking");
        setCurrentTxHash(null);

        // Start the approval/mint flow
        await executeNextStep();
      } catch (err) {
        setError(err as Error);
        setStatus("error");
      }
    },
    [optionAddress, collateralAddress, collateralDecimals, option?.isExpired, executeNextStep]
  );

  const reset = useCallback(() => {
    setStatus("idle");
    setError(null);
    setCurrentTxHash(null);
    setMintAmount(0n);
  }, []);

  return {
    // Action
    mint,
    reset,

    // State
    status,
    error,
    txHash: currentTxHash,
    isLoading: status !== "idle" && status !== "success" && status !== "error",
    isSuccess: status === "success",

    // Allowance visibility (for UI to show approval status)
    allowances: {
      erc20: allowances.erc20Allowance,
      factory: allowances.factoryAllowance,
      needsErc20: allowances.needsErc20Approval,
      needsFactory: allowances.needsFactoryApproval,
      isFullyApproved: allowances.isFullyApproved,
    },
  };
}

export default useMintWithApprovals;
