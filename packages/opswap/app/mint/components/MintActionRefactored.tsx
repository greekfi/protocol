import { useState, useCallback, useEffect } from "react";
import { Address, formatUnits, parseUnits } from "viem";
import { useOption } from "../hooks/useOption";
import { useAllowances } from "../hooks/useAllowances";
import { useApprove } from "../hooks/useApprove";
import { useMintAction } from "../hooks/useMintAction";
import { useWaitForTransactionReceipt } from "wagmi";

interface MintActionProps {
  optionAddress: Address | undefined;
}

/**
 * Refactored MintAction that separates concerns:
 * - Allowance state lives here and is checked explicitly
 * - Component decides what step to take based on state
 * - Each action (approve, mint) is a simple transaction call
 */
export function MintActionRefactored({ optionAddress }: MintActionProps) {
  const [amount, setAmount] = useState("");
  const [amountWei, setAmountWei] = useState(0n);

  // State machine for the mint flow
  const [flowState, setFlowState] = useState<
    | "idle"
    | "checking"
    | "needs-erc20"
    | "approving-erc20"
    | "needs-factory"
    | "approving-factory"
    | "ready-to-mint"
    | "minting"
    | "success"
    | "error"
  >("idle");
  const [error, setError] = useState<Error | null>(null);

  // Data hooks
  const { data: option, refetch: refetchOption } = useOption(optionAddress);
  const collateralAddress = option?.collateral.address;
  const collateralDecimals = option?.collateral.decimals ?? 18;

  // Allowance state - lives at application level
  const {
    erc20Allowance,
    factoryAllowance,
    needsErc20Approval,
    needsFactoryApproval,
    isFullyApproved,
    isLoading: allowancesLoading,
    refetch: refetchAllowances,
  } = useAllowances(collateralAddress, amountWei);

  // Action hooks - simple transaction executors
  const { approveErc20, approveFactory, txHash: approveTxHash } = useApprove();
  const { mint: executeMint, txHash: mintTxHash, isConfirmed: mintConfirmed } = useMintAction();

  // Wait for approval confirmations
  const { isSuccess: erc20Confirmed } = useWaitForTransactionReceipt({
    hash: flowState === "approving-erc20" ? approveTxHash ?? undefined : undefined,
  });

  const { isSuccess: factoryConfirmed } = useWaitForTransactionReceipt({
    hash: flowState === "approving-factory" ? approveTxHash ?? undefined : undefined,
  });

  // Flow control based on state changes
  useEffect(() => {
    if (flowState === "checking") {
      if (isFullyApproved) {
        setFlowState("ready-to-mint");
      } else if (needsErc20Approval) {
        setFlowState("needs-erc20");
      } else if (needsFactoryApproval) {
        setFlowState("needs-factory");
      }
    }
  }, [flowState, isFullyApproved, needsErc20Approval, needsFactoryApproval]);

  // Handle ERC20 approval confirmation
  useEffect(() => {
    if (flowState === "approving-erc20" && erc20Confirmed) {
      refetchAllowances();
      // Check if factory approval is still needed
      setFlowState("checking");
    }
  }, [flowState, erc20Confirmed, refetchAllowances]);

  // Handle factory approval confirmation
  useEffect(() => {
    if (flowState === "approving-factory" && factoryConfirmed) {
      refetchAllowances();
      setFlowState("ready-to-mint");
    }
  }, [flowState, factoryConfirmed, refetchAllowances]);

  // Handle mint confirmation
  useEffect(() => {
    if (flowState === "minting" && mintConfirmed) {
      refetchOption();
      setFlowState("success");
    }
  }, [flowState, mintConfirmed, refetchOption]);

  // Main action handler - orchestrates the flow
  const handleAction = useCallback(async () => {
    if (!collateralAddress || !optionAddress) return;

    try {
      setError(null);

      if (flowState === "idle") {
        // Parse amount and start checking
        const wei = parseUnits(amount, collateralDecimals);
        if (wei <= 0n) {
          setError(new Error("Amount must be greater than 0"));
          return;
        }
        setAmountWei(wei);
        setFlowState("checking");
        return;
      }

      if (flowState === "needs-erc20") {
        setFlowState("approving-erc20");
        await approveErc20(collateralAddress);
        return;
      }

      if (flowState === "needs-factory") {
        setFlowState("approving-factory");
        await approveFactory(collateralAddress);
        return;
      }

      if (flowState === "ready-to-mint") {
        setFlowState("minting");
        await executeMint(optionAddress, amountWei);
        return;
      }

      if (flowState === "success") {
        // Reset
        setFlowState("idle");
        setAmount("");
        setAmountWei(0n);
        return;
      }
    } catch (err) {
      setError(err as Error);
      setFlowState("error");
    }
  }, [
    flowState,
    amount,
    amountWei,
    collateralAddress,
    collateralDecimals,
    optionAddress,
    approveErc20,
    approveFactory,
    executeMint,
  ]);

  // Format balance for display
  const formatBalance = (balance: bigint | undefined, decimals: number): string => {
    if (!balance) return "0";
    return parseFloat(formatUnits(balance, decimals)).toFixed(4);
  };

  // Get button text based on state
  const getButtonText = () => {
    switch (flowState) {
      case "idle":
        return "Mint Options";
      case "checking":
        return "Checking allowances...";
      case "needs-erc20":
        return `Approve ${option?.collateral.symbol} to Factory`;
      case "approving-erc20":
        return "Approving ERC20...";
      case "needs-factory":
        return "Approve Factory for Token";
      case "approving-factory":
        return "Approving Factory...";
      case "ready-to-mint":
        return "Mint Options";
      case "minting":
        return "Minting...";
      case "success":
        return "Success! Click to reset";
      case "error":
        return "Error - Click to retry";
      default:
        return "Mint Options";
    }
  };

  const isLoading = [
    "checking",
    "approving-erc20",
    "approving-factory",
    "minting",
  ].includes(flowState);
  const isDisabled = isLoading || !amount || parseFloat(amount) <= 0 || option?.isExpired;

  if (!option) {
    return (
      <div className="p-6 bg-black/80 border border-gray-800 rounded-lg shadow-lg">
        <h2 className="text-xl font-light text-blue-300 mb-4">Mint Options</h2>
        <div className="text-gray-400">Select an option to mint</div>
      </div>
    );
  }

  return (
    <div className="p-6 bg-black/80 border border-gray-800 rounded-lg shadow-lg">
      <h2 className="text-xl font-light text-blue-300 mb-4">Mint Options</h2>

      {/* Balances */}
      <div className="space-y-2 mb-4">
        <div className="flex justify-between text-sm">
          <span className="text-gray-400">Collateral ({option.collateral.symbol})</span>
          <span className="text-blue-300">{formatBalance(option.balances?.collateral, option.collateral.decimals)}</span>
        </div>
        <div className="flex justify-between text-sm">
          <span className="text-gray-400">Option Balance</span>
          <span className="text-blue-300">{formatBalance(option.balances?.option, 18)}</span>
        </div>
        <div className="flex justify-between text-sm">
          <span className="text-gray-400">Redemption Balance</span>
          <span className="text-blue-300">{formatBalance(option.balances?.redemption, 18)}</span>
        </div>
      </div>

      {/* Allowance Status - Visible to user */}
      {amountWei > 0n && flowState !== "idle" && flowState !== "success" && (
        <div className="mb-4 p-3 bg-gray-900 rounded-lg text-xs space-y-1">
          <div className="flex justify-between">
            <span className="text-gray-400">ERC20 Allowance:</span>
            <span className={needsErc20Approval ? "text-yellow-500" : "text-green-500"}>
              {needsErc20Approval ? "❌ Needs approval" : "✓ Approved"}
            </span>
          </div>
          <div className="flex justify-between">
            <span className="text-gray-400">Factory Allowance:</span>
            <span className={needsFactoryApproval ? "text-yellow-500" : "text-green-500"}>
              {needsFactoryApproval ? "❌ Needs approval" : "✓ Approved"}
            </span>
          </div>
        </div>
      )}

      {/* Amount Input */}
      <div className="mb-4">
        <label className="block text-sm text-gray-400 mb-1">Amount to mint ({option.collateral.symbol})</label>
        <input
          type="number"
          value={amount}
          onChange={(e) => setAmount(e.target.value)}
          placeholder="0.0"
          className="w-full p-2 rounded-lg border border-gray-700 bg-black/60 text-blue-300"
          disabled={isLoading}
          min="0"
          step="0.01"
        />
      </div>

      {/* Error Display */}
      {error && <div className="text-red-400 text-sm mb-4">{error.message}</div>}

      {/* Success Display */}
      {flowState === "success" && mintTxHash && (
        <div className="text-green-400 text-sm mb-4">
          Mint successful!
          <br />
          <span className="text-gray-500 text-xs">
            Tx: {mintTxHash.slice(0, 10)}...{mintTxHash.slice(-8)}
          </span>
        </div>
      )}

      {/* Action Button */}
      <button
        onClick={handleAction}
        disabled={isDisabled && flowState !== "success" && flowState !== "error"}
        className={`w-full py-2 rounded-lg transition-colors ${
          isDisabled && flowState !== "success" && flowState !== "error"
            ? "bg-gray-600 cursor-not-allowed text-gray-400"
            : flowState === "success"
            ? "bg-green-600 hover:bg-green-700 text-white"
            : flowState === "error"
            ? "bg-red-600 hover:bg-red-700 text-white"
            : "bg-blue-500 hover:bg-blue-600 text-white"
        }`}
      >
        {getButtonText()}
      </button>

      {/* Expired Warning */}
      {option.isExpired && (
        <div className="mt-2 text-yellow-500 text-sm text-center">This option has expired and cannot be minted</div>
      )}

      {/* Debug Info (remove in production) */}
      <details className="mt-4 text-xs text-gray-500">
        <summary className="cursor-pointer">Debug Info</summary>
        <div className="mt-2 space-y-1">
          <div>Flow State: {flowState}</div>
          <div>Amount Wei: {amountWei.toString()}</div>
          <div>ERC20 Allowance: {erc20Allowance.toString()}</div>
          <div>Factory Allowance: {factoryAllowance.toString()}</div>
          <div>Fully Approved: {isFullyApproved ? "Yes" : "No"}</div>
        </div>
      </details>
    </div>
  );
}

export default MintActionRefactored;
