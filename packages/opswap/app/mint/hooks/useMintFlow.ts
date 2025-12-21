import { useState, useCallback, useEffect } from "react";
import { Address, parseUnits } from "viem";
import { useWaitForTransactionReceipt } from "wagmi";
import { useAllowances } from "./useAllowances";
import { useApprove } from "./useApprove";
import { useMintAction } from "./useMintAction";
import { useOption } from "./useOption";

export type MintFlowState =
  | "idle"
  | "input" // User is entering amount
  | "checking-allowances" // Checking what approvals are needed
  | "needs-erc20-approval" // Need to approve ERC20
  | "approving-erc20" // Approving ERC20
  | "waiting-erc20" // Waiting for ERC20 approval confirmation
  | "needs-factory-approval" // Need to approve factory
  | "approving-factory" // Approving factory
  | "waiting-factory" // Waiting for factory approval confirmation
  | "ready-to-mint" // All approvals done, ready to mint
  | "minting" // Minting in progress
  | "waiting-mint" // Waiting for mint confirmation
  | "success" // Mint successful
  | "error"; // Error occurred

export interface MintFlowData {
  // Flow state
  state: MintFlowState;
  error: Error | null;

  // Amount data
  amount: string; // Human-readable amount (e.g., "1.5")
  amountWei: bigint; // Amount in wei

  // Allowance data (from useAllowances)
  erc20Allowance: bigint;
  factoryAllowance: bigint;
  needsErc20Approval: boolean;
  needsFactoryApproval: boolean;
  isFullyApproved: boolean;

  // Transaction hashes
  erc20ApprovalTxHash: `0x${string}` | null;
  factoryApprovalTxHash: `0x${string}` | null;
  mintTxHash: `0x${string}` | null;

  // Actions
  setAmount: (amount: string) => void;
  startMintFlow: () => void;
  executeCurrentStep: () => Promise<void>;
  reset: () => void;
}

/**
 * Central state management for the mint flow
 * All state lives here - components are purely presentational
 *
 * Usage:
 * const mintFlow = useMintFlow(optionAddress);
 * // Pass mintFlow to components
 * <MintAction mintFlow={mintFlow} option={option} />
 */
export function useMintFlow(optionAddress: Address | undefined): MintFlowData {
  // State
  const [state, setState] = useState<MintFlowState>("idle");
  const [error, setError] = useState<Error | null>(null);
  const [amount, setAmount] = useState("");
  const [amountWei, setAmountWei] = useState(0n);

  // Data from hooks
  const { data: option, refetch: refetchOption } = useOption(optionAddress);
  const collateralAddress = option?.collateral.address;
  const collateralDecimals = option?.collateral.decimals ?? 18;

  // Allowances - this is the source of truth for approval state
  const allowances = useAllowances(collateralAddress, amountWei);

  // Actions
  const { approveErc20, approveFactory, txHash: approveTxHash } = useApprove();
  const { mint: executeMint, txHash: mintTxHash } = useMintAction();

  // Track which transaction hash corresponds to which approval
  const [erc20ApprovalTxHash, setErc20ApprovalTxHash] = useState<`0x${string}` | null>(null);
  const [factoryApprovalTxHash, setFactoryApprovalTxHash] = useState<`0x${string}` | null>(null);

  // Wait for ERC20 approval
  const { isSuccess: erc20Confirmed } = useWaitForTransactionReceipt({
    hash: erc20ApprovalTxHash ?? undefined,
  });

  // Wait for factory approval
  const { isSuccess: factoryConfirmed } = useWaitForTransactionReceipt({
    hash: factoryApprovalTxHash ?? undefined,
  });

  // Wait for mint
  const { isSuccess: mintConfirmed } = useWaitForTransactionReceipt({
    hash: mintTxHash ?? undefined,
  });

  // ========== FLOW CONTROL ==========

  // Auto-transition based on allowance checks
  useEffect(() => {
    if (state === "checking-allowances") {
      if (allowances.isFullyApproved) {
        setState("ready-to-mint");
      } else if (allowances.needsErc20Approval) {
        setState("needs-erc20-approval");
      } else if (allowances.needsFactoryApproval) {
        setState("needs-factory-approval");
      }
    }
  }, [state, allowances.isFullyApproved, allowances.needsErc20Approval, allowances.needsFactoryApproval]);

  // Handle ERC20 approval confirmation
  useEffect(() => {
    if (state === "waiting-erc20" && erc20Confirmed) {
      allowances.refetch();
      setState("checking-allowances");
    }
  }, [state, erc20Confirmed, allowances]);

  // Handle factory approval confirmation
  useEffect(() => {
    if (state === "waiting-factory" && factoryConfirmed) {
      allowances.refetch();
      setState("ready-to-mint");
    }
  }, [state, factoryConfirmed, allowances]);

  // Handle mint confirmation
  useEffect(() => {
    if (state === "waiting-mint" && mintConfirmed) {
      refetchOption();
      allowances.refetch();
      setState("success");
    }
  }, [state, mintConfirmed, refetchOption, allowances]);

  // ========== ACTIONS ==========

  const startMintFlow = useCallback(() => {
    if (!amount || parseFloat(amount) <= 0) {
      setError(new Error("Please enter a valid amount"));
      return;
    }

    if (option?.isExpired) {
      setError(new Error("Option has expired"));
      return;
    }

    try {
      const wei = parseUnits(amount, collateralDecimals);
      setAmountWei(wei);
      setError(null);
      setState("checking-allowances");
    } catch (err) {
      setError(err as Error);
      setState("error");
    }
  }, [amount, collateralDecimals, option?.isExpired]);

  const executeCurrentStep = useCallback(async () => {
    if (!collateralAddress || !optionAddress) {
      setError(new Error("Missing addresses"));
      setState("error");
      return;
    }

    try {
      setError(null);

      switch (state) {
        case "needs-erc20-approval":
          setState("approving-erc20");
          const erc20Hash = await approveErc20(collateralAddress);
          if (erc20Hash) {
            setErc20ApprovalTxHash(erc20Hash);
            setState("waiting-erc20");
          }
          break;

        case "needs-factory-approval":
          setState("approving-factory");
          const factoryHash = await approveFactory(collateralAddress);
          if (factoryHash) {
            setFactoryApprovalTxHash(factoryHash);
            setState("waiting-factory");
          }
          break;

        case "ready-to-mint":
          setState("minting");
          await executeMint(optionAddress, amountWei);
          setState("waiting-mint");
          break;

        default:
          // No action needed
          break;
      }
    } catch (err) {
      setError(err as Error);
      setState("error");
    }
  }, [state, collateralAddress, optionAddress, amountWei, approveErc20, approveFactory, executeMint]);

  const reset = useCallback(() => {
    setState("idle");
    setError(null);
    setAmount("");
    setAmountWei(0n);
    setErc20ApprovalTxHash(null);
    setFactoryApprovalTxHash(null);
  }, []);

  return {
    // State
    state,
    error,

    // Amount
    amount,
    amountWei,

    // Allowances
    erc20Allowance: allowances.erc20Allowance,
    factoryAllowance: allowances.factoryAllowance,
    needsErc20Approval: allowances.needsErc20Approval,
    needsFactoryApproval: allowances.needsFactoryApproval,
    isFullyApproved: allowances.isFullyApproved,

    // Tx hashes
    erc20ApprovalTxHash,
    factoryApprovalTxHash,
    mintTxHash,

    // Actions
    setAmount,
    startMintFlow,
    executeCurrentStep,
    reset,
  };
}

export default useMintFlow;
