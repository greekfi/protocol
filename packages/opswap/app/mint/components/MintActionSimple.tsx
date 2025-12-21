import { useState } from "react";
import { Address, formatUnits } from "viem";
import { useOption } from "../hooks/useOption";
import { useMintWithApprovals } from "../hooks/useMintWithApprovals";

interface MintActionProps {
  optionAddress: Address | undefined;
}

/**
 * Simple Mint component
 * - User enters amount
 * - Clicks "Mint"
 * - Component automatically handles all approvals
 * - Shows status as it progresses
 */
export function MintActionSimple({ optionAddress }: MintActionProps) {
  const [amount, setAmount] = useState("");

  const { data: option } = useOption(optionAddress);
  const { mint, reset, status, error, txHash, allowances } = useMintWithApprovals(optionAddress);

  const handleMint = async () => {
    if (!amount || parseFloat(amount) <= 0) return;
    await mint(amount);
  };

  const handleReset = () => {
    reset();
    setAmount("");
  };

  const formatBalance = (balance: bigint | undefined, decimals: number): string => {
    if (!balance) return "0";
    return parseFloat(formatUnits(balance, decimals)).toFixed(4);
  };

  const getButtonText = () => {
    switch (status) {
      case "idle":
        return "Mint Options";
      case "checking":
        return "Checking approvals...";
      case "approving-erc20":
        return "Approving token...";
      case "approving-factory":
        return "Approving factory...";
      case "minting":
        return "Minting...";
      case "success":
        return "Success! Click to mint again";
      case "error":
        return "Error - Click to retry";
      default:
        return "Mint Options";
    }
  };

  const isLoading = ["checking", "approving-erc20", "approving-factory", "minting"].includes(status);
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

      {/* Approval Status - Only show when actively minting */}
      {status !== "idle" && status !== "success" && (
        <div className="mb-4 p-3 bg-gray-900 rounded-lg text-xs space-y-1">
          <div className="font-semibold text-gray-300 mb-2">Approval Status:</div>
          <div className="flex justify-between items-center">
            <span className="text-gray-400">Token → Factory:</span>
            <span className={allowances.needsErc20 ? "text-yellow-500" : "text-green-500"}>
              {allowances.needsErc20 ? "⏳ Pending" : "✓ Approved"}
            </span>
          </div>
          <div className="flex justify-between items-center">
            <span className="text-gray-400">Factory → Token:</span>
            <span className={allowances.needsFactory ? "text-yellow-500" : "text-green-500"}>
              {allowances.needsFactory ? "⏳ Pending" : "✓ Approved"}
            </span>
          </div>
        </div>
      )}

      {/* Amount Input */}
      <div className="mb-4">
        <label className="block text-sm text-gray-400 mb-1">Amount ({option.collateral.symbol})</label>
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

      {/* Error */}
      {error && (
        <div className="text-red-400 text-sm mb-4 p-2 bg-red-900/20 rounded border border-red-800">{error.message}</div>
      )}

      {/* Success */}
      {status === "success" && txHash && (
        <div className="text-green-400 text-sm mb-4 p-2 bg-green-900/20 rounded border border-green-800">
          ✓ Minted successfully!
          <br />
          <span className="text-gray-500 text-xs">
            Tx: {txHash.slice(0, 10)}...{txHash.slice(-8)}
          </span>
        </div>
      )}

      {/* Action Button */}
      <button
        onClick={status === "success" ? handleReset : handleMint}
        disabled={isDisabled && status !== "success"}
        className={`w-full py-2 px-4 rounded-lg transition-colors font-medium ${
          isDisabled && status !== "success"
            ? "bg-gray-600 cursor-not-allowed text-gray-400"
            : status === "success"
            ? "bg-green-600 hover:bg-green-700 text-white"
            : status === "error"
            ? "bg-red-600 hover:bg-red-700 text-white"
            : "bg-blue-500 hover:bg-blue-600 text-white"
        }`}
      >
        {getButtonText()}
      </button>

      {/* Expired Warning */}
      {option.isExpired && (
        <div className="mt-2 text-yellow-500 text-sm text-center p-2 bg-yellow-900/20 rounded border border-yellow-800">
          ⚠️ This option has expired
        </div>
      )}
    </div>
  );
}

export default MintActionSimple;
