import { useState, useCallback } from "react";
import { Address, formatUnits } from "viem";
import { useMint } from "../hooks/useMint";
import { useOption } from "../hooks/useOption";
import { getStepLabel, getStepProgress } from "../hooks/useTransactionFlow";

interface MintActionProps {
  optionAddress: Address | undefined;
}

export function MintAction({ optionAddress }: MintActionProps) {
  const [amount, setAmount] = useState("");

  const { data: option } = useOption(optionAddress);
  const { mint, step, isLoading, isSuccess, error, txHash, reset } = useMint(optionAddress);

  const handleMint = useCallback(async () => {
    if (!amount || parseFloat(amount) <= 0) return;
    await mint(amount);
  }, [amount, mint]);

  const handleReset = useCallback(() => {
    reset();
    setAmount("");
  }, [reset]);

  // Format balance for display
  const formatBalance = (balance: bigint | undefined, decimals: number): string => {
    if (!balance) return "0";
    return parseFloat(formatUnits(balance, decimals)).toFixed(4);
  };

  const getButtonText = () => {
    if (isLoading) return getStepLabel(step);
    if (isSuccess) return "Minted! Click to reset";
    if (option?.isExpired) return "Option Expired";
    return "Mint Options";
  };

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
      {isSuccess && txHash && (
        <div className="text-green-400 text-sm mb-4">
          Mint successful!
          <br />
          <span className="text-gray-500 text-xs">Tx: {txHash.slice(0, 10)}...{txHash.slice(-8)}</span>
        </div>
      )}

      {/* Progress Bar */}
      {isLoading && (
        <div className="mb-4">
          <div className="flex justify-between text-xs text-gray-400 mb-1">
            <span>{getStepLabel(step)}</span>
            <span>{getStepProgress(step)}%</span>
          </div>
          <div className="w-full bg-gray-700 rounded-full h-2">
            <div
              className="bg-blue-500 h-2 rounded-full transition-all duration-300"
              style={{ width: `${getStepProgress(step)}%` }}
            />
          </div>
        </div>
      )}

      {/* Action Button */}
      <button
        onClick={isSuccess ? handleReset : handleMint}
        disabled={isDisabled && !isSuccess}
        className={`w-full py-2 rounded-lg transition-colors ${
          isDisabled && !isSuccess
            ? "bg-gray-600 cursor-not-allowed text-gray-400"
            : isSuccess
            ? "bg-green-600 hover:bg-green-700 text-white"
            : "bg-blue-500 hover:bg-blue-600 text-white"
        }`}
      >
        {getButtonText()}
      </button>

      {/* Expired Warning */}
      {option.isExpired && (
        <div className="mt-2 text-yellow-500 text-sm text-center">This option has expired and cannot be minted</div>
      )}
    </div>
  );
}

export default MintAction;
