import { formatUnits } from "viem";
import type { MintFlowData, MintFlowState } from "../hooks/useMintFlow";
import type { OptionDetails } from "../hooks/types";

interface MintActionProps {
  option: OptionDetails | null;
  mintFlow: MintFlowData;
}

/**
 * Purely presentational Mint component
 * All state comes from props - no hooks, no logic
 */
export function MintActionPresentational({ option, mintFlow }: MintActionProps) {
  const {
    state,
    error,
    amount,
    erc20Allowance,
    factoryAllowance,
    needsErc20Approval,
    needsFactoryApproval,
    isFullyApproved,
    mintTxHash,
    setAmount,
    startMintFlow,
    executeCurrentStep,
    reset,
  } = mintFlow;

  // Format balance for display
  const formatBalance = (balance: bigint | undefined, decimals: number): string => {
    if (!balance) return "0";
    return parseFloat(formatUnits(balance, decimals)).toFixed(4);
  };

  // Get button text based on state
  const getButtonText = (state: MintFlowState): string => {
    switch (state) {
      case "idle":
      case "input":
        return "Mint Options";
      case "checking-allowances":
        return "Checking allowances...";
      case "needs-erc20-approval":
        return `Approve ${option?.collateral.symbol} to Factory`;
      case "approving-erc20":
        return "Approving ERC20...";
      case "waiting-erc20":
        return "Waiting for ERC20 confirmation...";
      case "needs-factory-approval":
        return "Approve Factory for Token";
      case "approving-factory":
        return "Approving Factory...";
      case "waiting-factory":
        return "Waiting for Factory confirmation...";
      case "ready-to-mint":
        return "Mint Options";
      case "minting":
        return "Minting...";
      case "waiting-mint":
        return "Waiting for Mint confirmation...";
      case "success":
        return "Success! Click to reset";
      case "error":
        return "Error - Click to retry";
      default:
        return "Mint Options";
    }
  };

  // Determine what happens on button click
  const handleButtonClick = () => {
    if (state === "idle" || state === "input") {
      startMintFlow();
    } else if (state === "success") {
      reset();
    } else if (state === "error") {
      reset();
    } else if (
      state === "needs-erc20-approval" ||
      state === "needs-factory-approval" ||
      state === "ready-to-mint"
    ) {
      executeCurrentStep();
    }
  };

  const isLoading = [
    "checking-allowances",
    "approving-erc20",
    "waiting-erc20",
    "approving-factory",
    "waiting-factory",
    "minting",
    "waiting-mint",
  ].includes(state);

  const isDisabled =
    (isLoading && state !== "needs-erc20-approval" && state !== "needs-factory-approval" && state !== "ready-to-mint") ||
    !amount ||
    parseFloat(amount) <= 0 ||
    option?.isExpired;

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

      {/* Allowance Status */}
      {state !== "idle" && state !== "success" && state !== "input" && (
        <div className="mb-4 p-3 bg-gray-900 rounded-lg text-xs space-y-1">
          <div className="font-semibold text-gray-300 mb-2">Approval Status:</div>
          <div className="flex justify-between items-center">
            <span className="text-gray-400">ERC20 → Factory:</span>
            <div className="flex items-center gap-2">
              <span className="text-gray-500 text-xs">{erc20Allowance > 0n ? "∞" : "0"}</span>
              <span className={needsErc20Approval ? "text-yellow-500" : "text-green-500"}>
                {needsErc20Approval ? "❌" : "✓"}
              </span>
            </div>
          </div>
          <div className="flex justify-between items-center">
            <span className="text-gray-400">Factory → Token:</span>
            <div className="flex items-center gap-2">
              <span className="text-gray-500 text-xs">{factoryAllowance > 0n ? "∞" : "0"}</span>
              <span className={needsFactoryApproval ? "text-yellow-500" : "text-green-500"}>
                {needsFactoryApproval ? "❌" : "✓"}
              </span>
            </div>
          </div>
          {isFullyApproved && (
            <div className="text-green-500 text-center mt-2 font-semibold">✓ All approvals complete!</div>
          )}
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
      {error && (
        <div className="text-red-400 text-sm mb-4 p-2 bg-red-900/20 rounded border border-red-800">{error.message}</div>
      )}

      {/* Success Display */}
      {state === "success" && mintTxHash && (
        <div className="text-green-400 text-sm mb-4 p-2 bg-green-900/20 rounded border border-green-800">
          ✓ Mint successful!
          <br />
          <span className="text-gray-500 text-xs">
            Tx: {mintTxHash.slice(0, 10)}...{mintTxHash.slice(-8)}
          </span>
        </div>
      )}

      {/* Action Button */}
      <button
        onClick={handleButtonClick}
        disabled={isDisabled && state !== "success" && state !== "error"}
        className={`w-full py-2 px-4 rounded-lg transition-colors font-medium ${
          isDisabled && state !== "success" && state !== "error"
            ? "bg-gray-600 cursor-not-allowed text-gray-400"
            : state === "success"
            ? "bg-green-600 hover:bg-green-700 text-white"
            : state === "error"
            ? "bg-red-600 hover:bg-red-700 text-white"
            : state === "needs-erc20-approval" || state === "needs-factory-approval"
            ? "bg-yellow-600 hover:bg-yellow-700 text-white"
            : "bg-blue-500 hover:bg-blue-600 text-white"
        }`}
      >
        {getButtonText(state)}
      </button>

      {/* Expired Warning */}
      {option.isExpired && (
        <div className="mt-2 text-yellow-500 text-sm text-center p-2 bg-yellow-900/20 rounded border border-yellow-800">
          ⚠️ This option has expired and cannot be minted
        </div>
      )}

      {/* Current State Debug */}
      <div className="mt-3 text-xs text-gray-500 text-center">State: {state}</div>
    </div>
  );
}

export default MintActionPresentational;
