import { useState } from "react";
import { useTransferOption } from "../hooks/transactions/useTransferOption";
import { useOption } from "../hooks/useOption";
import { Address, formatUnits, isAddress, parseUnits } from "viem";
import { useWaitForTransactionReceipt } from "wagmi";

interface TransferOptionProps {
  optionAddress: Address | undefined;
}

/**
 * Transfer Option tokens to another address
 */
export function TransferOption({ optionAddress }: TransferOptionProps) {
  const [recipient, setRecipient] = useState("");
  const [amount, setAmount] = useState("");
  const [txHash, setTxHash] = useState<`0x${string}` | null>(null);
  const [status, setStatus] = useState<"idle" | "working" | "success" | "error">("idle");
  const [error, setError] = useState<string | null>(null);

  // Data fetching
  const { data: option, refetch: refetchOption } = useOption(optionAddress);

  // Transaction executor
  const transferTx = useTransferOption();

  // Wait for transaction
  const { isSuccess: txConfirmed, isError: txFailed } = useWaitForTransactionReceipt({
    hash: txHash ?? undefined,
    query: { enabled: Boolean(txHash) },
  });

  // Reset when transaction confirms or fails
  if (txHash && txConfirmed) {
    setTxHash(null);
    if (status === "working") {
      setStatus("success");
      refetchOption();
    }
  }

  if (txHash && txFailed) {
    setTxHash(null);
    setStatus("error");
    setError("Transaction failed");
  }

  const handleTransfer = async () => {
    if (!optionAddress || !option) return;
    if (!recipient || !amount || parseFloat(amount) <= 0) return;

    // Validate recipient address
    if (!isAddress(recipient)) {
      setError("Invalid recipient address");
      setStatus("error");
      return;
    }

    try {
      setStatus("working");
      setError(null);

      const wei = parseUnits(amount, 18); // Options are 18 decimals

      // Check balance
      if (option.balances?.option && option.balances.option < wei) {
        setError("Insufficient Option token balance");
        setStatus("error");
        return;
      }

      // Transfer
      const hash = await transferTx.transfer(optionAddress, recipient as Address, wei);
      setTxHash(hash);
    } catch (err: any) {
      setStatus("error");
      setError(err.message || "Transaction failed");
    }
  };

  const handleReset = () => {
    setStatus("idle");
    setError(null);
    setRecipient("");
    setAmount("");
    setTxHash(null);
  };

  if (!option) {
    return (
      <div className="p-6 bg-black/80 border border-gray-800 rounded-lg shadow-lg">
        <h2 className="text-xl font-light text-blue-300 mb-4">Transfer Options</h2>
        <div className="text-gray-400">Select an option to transfer</div>
      </div>
    );
  }

  const formatBalance = (balance: bigint | undefined, decimals: number): string => {
    if (!balance) return "0";
    return parseFloat(formatUnits(balance, decimals)).toFixed(4);
  };

  const getStatusText = () => {
    if (status === "success") return "Success!";
    if (status === "error") return "Error";
    if (status === "working") return "Transferring...";
    return "Transfer Options";
  };

  return (
    <div className="p-6 bg-black/80 border border-gray-800 rounded-lg shadow-lg">
      <h2 className="text-xl font-light text-blue-300 mb-4">Transfer Options</h2>

      {/* Balance */}
      <div className="space-y-2 mb-4">
        <div className="flex justify-between text-sm">
          <span className="text-gray-400">Your Option Balance</span>
          <span className="text-blue-300">{formatBalance(option.balances?.option, option.collateral.decimals)}</span>
        </div>
      </div>

      {/* Recipient Input */}
      <div className="mb-4">
        <label className="block text-sm text-gray-400 mb-1">Recipient Address</label>
        <input
          type="text"
          value={recipient}
          onChange={e => setRecipient(e.target.value)}
          placeholder="0x..."
          className="w-full p-2 rounded-lg border border-gray-700 bg-black/60 text-blue-300 font-mono text-sm"
          disabled={status === "working"}
        />
      </div>

      {/* Amount Input */}
      <div className="mb-4">
        <div className="flex justify-between items-center mb-1">
          <label className="block text-sm text-gray-400">Amount</label>
          <button
            onClick={() => setAmount(formatUnits(option.balances?.option ?? 0n, 18))}
            className="text-xs text-blue-400 hover:text-blue-300 underline"
            disabled={status === "working"}
          >
            Max
          </button>
        </div>
        <input
          type="number"
          value={amount}
          onChange={e => setAmount(e.target.value)}
          placeholder="0.0"
          className="w-full p-2 rounded-lg border border-gray-700 bg-black/60 text-blue-300"
          disabled={status === "working"}
          min="0"
          step="0.01"
        />
      </div>

      {/* Error */}
      {error && (
        <div className="text-red-400 text-sm mb-4 p-2 bg-red-900/20 rounded border border-red-800">{error}</div>
      )}

      {/* Success */}
      {status === "success" && (
        <div className="text-green-400 text-sm mb-4 p-2 bg-green-900/20 rounded border border-green-800">
          ✓ Transferred successfully!
        </div>
      )}

      {/* Action Button */}
      <button
        onClick={status === "success" ? handleReset : handleTransfer}
        disabled={
          status === "working" ||
          !recipient ||
          !amount ||
          parseFloat(amount) <= 0 ||
          !isAddress(recipient) ||
          option.isExpired
        }
        className={`w-full py-2 px-4 rounded-lg transition-colors font-medium ${
          status === "working" ||
          !recipient ||
          !amount ||
          parseFloat(amount) <= 0 ||
          !isAddress(recipient) ||
          option.isExpired
            ? "bg-gray-600 cursor-not-allowed text-gray-400"
            : status === "success"
              ? "bg-green-600 hover:bg-green-700 text-white"
              : status === "error"
                ? "bg-red-600 hover:bg-red-700 text-white"
                : "bg-blue-500 hover:bg-blue-600 text-white"
        }`}
      >
        {getStatusText()}
      </button>

      {/* Warning */}
      {option.isExpired && (
        <div className="mt-2 text-yellow-500 text-sm text-center p-2 bg-yellow-900/20 rounded border border-yellow-800">
          ⚠️ This option has expired
        </div>
      )}
    </div>
  );
}

export default TransferOption;
