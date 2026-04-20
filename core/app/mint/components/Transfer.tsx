import { useState } from "react";
import { useOption } from "../hooks/useOption";
import { Address, formatUnits, isAddress, parseUnits } from "viem";
import { useWaitForTransactionReceipt } from "wagmi";
import { useWriteCollateralTransfer, useWriteOptionTransfer } from "~~/generated";

interface TransferProps {
  optionAddress: Address | undefined;
}

type Side = "option" | "clt";

/**
 * Unified transfer UI for both the long (Option) and short (CLT — Collateral Token) positions.
 * CLT is the ERC20 "Collateral" clone the factory deploys for the short side.
 */
export function Transfer({ optionAddress }: TransferProps) {
  const [side, setSide] = useState<Side>("option");
  const [recipient, setRecipient] = useState("");
  const [amount, setAmount] = useState("");
  const [txHash, setTxHash] = useState<`0x${string}` | null>(null);
  const [status, setStatus] = useState<"idle" | "working" | "success" | "error">("idle");
  const [error, setError] = useState<string | null>(null);

  const { data: option, refetch: refetchOption } = useOption(optionAddress);

  const { writeContractAsync: transferOption } = useWriteOptionTransfer();
  const { writeContractAsync: transferClt } = useWriteCollateralTransfer();

  const { isSuccess: txConfirmed, isError: txFailed } = useWaitForTransactionReceipt({
    hash: txHash ?? undefined,
    query: { enabled: Boolean(txHash) },
  });

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

  if (!option) {
    return (
      <div className="p-6 bg-black/80 border border-gray-800 rounded-lg shadow-lg">
        <h2 className="text-xl font-light text-purple-300 mb-4">Transfer</h2>
        <div className="text-gray-400">Select an option to transfer</div>
      </div>
    );
  }

  const balance = side === "option" ? option.balances?.option : option.balances?.coll;
  const sideLabel = side === "option" ? "Option" : "CLT";

  const handleTransfer = async () => {
    if (!optionAddress || !option) return;
    if (!recipient || !amount || parseFloat(amount) <= 0) return;
    if (!isAddress(recipient)) {
      setError("Invalid recipient address");
      setStatus("error");
      return;
    }

    try {
      setStatus("working");
      setError(null);
      const wei = parseUnits(amount, 18); // both tokens are 18-dec

      if (balance && balance < wei) {
        setError(`Insufficient ${sideLabel} balance`);
        setStatus("error");
        return;
      }

      const hash =
        side === "option"
          ? await transferOption({ address: optionAddress, args: [recipient as Address, wei] })
          : await transferClt({ address: option.coll, args: [recipient as Address, wei] });
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

  const formatBalance = (b: bigint | undefined, decimals: number): string =>
    b ? parseFloat(formatUnits(b, decimals)).toFixed(4) : "0";

  const getStatusText = () => {
    if (status === "success") return "Success!";
    if (status === "error") return "Error";
    if (status === "working") return "Transferring...";
    return `Transfer ${sideLabel}`;
  };

  return (
    <div className="p-6 bg-black/80 border border-gray-800 rounded-lg shadow-lg">
      <h2 className="text-xl font-light text-purple-300 mb-4">Transfer</h2>

      {/* Side selector */}
      <div className="flex gap-2 mb-4">
        <button
          type="button"
          onClick={() => setSide("option")}
          className={`flex-1 py-2 px-3 rounded text-sm transition-colors ${
            side === "option" ? "bg-blue-500 text-white" : "bg-gray-700 text-gray-300 hover:bg-gray-600"
          }`}
        >
          Option (Long)
        </button>
        <button
          type="button"
          onClick={() => setSide("clt")}
          className={`flex-1 py-2 px-3 rounded text-sm transition-colors ${
            side === "clt" ? "bg-purple-500 text-white" : "bg-gray-700 text-gray-300 hover:bg-gray-600"
          }`}
        >
          CLT (Short)
        </button>
      </div>

      {/* Balance */}
      <div className="space-y-2 mb-4">
        <div className="flex justify-between text-sm">
          <span className="text-gray-400">Your {sideLabel} Balance</span>
          <span className="text-purple-300">{formatBalance(balance, option.collateral.decimals)}</span>
        </div>
      </div>

      {/* Recipient */}
      <div className="mb-4">
        <label className="block text-sm text-gray-400 mb-1">Recipient Address</label>
        <input
          type="text"
          value={recipient}
          onChange={e => setRecipient(e.target.value)}
          placeholder="0x..."
          className="w-full p-2 rounded-lg border border-gray-700 bg-black/60 text-purple-300 font-mono text-sm"
          disabled={status === "working"}
        />
      </div>

      {/* Amount */}
      <div className="mb-4">
        <div className="flex justify-between items-center mb-1">
          <label className="block text-sm text-gray-400">Amount</label>
          <button
            onClick={() => setAmount(formatUnits(balance ?? 0n, 18))}
            className="text-xs text-purple-400 hover:text-purple-300 underline"
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
          className="w-full p-2 rounded-lg border border-gray-700 bg-black/60 text-purple-300"
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
                : "bg-purple-500 hover:bg-purple-600 text-white"
        }`}
      >
        {getStatusText()}
      </button>

      {option.isExpired && (
        <div className="mt-2 text-yellow-500 text-sm text-center p-2 bg-yellow-900/20 rounded border border-yellow-800">
          ⚠️ This option has expired
        </div>
      )}
    </div>
  );
}

export default Transfer;
