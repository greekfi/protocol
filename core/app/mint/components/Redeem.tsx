import { useState } from "react";
import { useRedeemTransaction } from "../hooks/transactions/useRedeemTransaction";
import { useOption } from "../hooks/useOption";
import { Address, formatUnits, parseUnits } from "viem";
import { useWaitForTransactionReceipt } from "wagmi";

interface RedeemActionProps {
  optionAddress: Address | undefined;
}

/**
 * Clean redeem component - all logic lives here, hooks are just data/transactions
 * Redeem burns matching Option + Redemption token pairs to get collateral back
 * No approvals needed - you already own both tokens
 */
export function Redeem({ optionAddress }: RedeemActionProps) {
  const [amount, setAmount] = useState("");
  const [txHash, setTxHash] = useState<`0x${string}` | null>(null);
  const [status, setStatus] = useState<"idle" | "working" | "success" | "error">("idle");
  const [error, setError] = useState<string | null>(null);

  // Data fetching (pure reads)
  const { data: option, refetch: refetchOption } = useOption(optionAddress);

  // Transaction executors (pure writes)
  const redeemTx = useRedeemTransaction();

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

  const handleRedeem = async () => {
    if (!optionAddress || !option) return;
    if (!amount || parseFloat(amount) <= 0) return;

    try {
      setStatus("working");
      setError(null);

      const wei = parseUnits(amount, 18); // Options are 18 decimals

      console.log("=== Redeem Debug ===");
      console.log("Amount entered:", amount);
      console.log("Amount in wei:", wei.toString());
      console.log("Option balance:", option.balances?.option?.toString());
      console.log("Redemption balance:", option.balances?.redemption?.toString());
      console.log("Option balance check:", option.balances?.option ? option.balances.option < wei : "no balance");
      console.log(
        "Redemption balance check:",
        option.balances?.redemption ? option.balances.redemption < wei : "no balance",
      );

      // Check if user has enough of both tokens
      if (option.balances?.option && option.balances.option < wei) {
        console.error("Failed: Insufficient Option balance");
        setError("Insufficient Option token balance");
        setStatus("error");
        return;
      }

      if (option.balances?.redemption && option.balances.redemption < wei) {
        console.error("Failed: Insufficient Redemption balance");
        setError("Insufficient Redemption token balance");
        setStatus("error");
        return;
      }

      // Redeem (no approvals needed)
      const hash = await redeemTx.redeem(optionAddress, wei);
      setTxHash(hash);
    } catch (err: any) {
      setStatus("error");
      setError(err.message || "Transaction failed");
    }
  };

  const handleReset = () => {
    setStatus("idle");
    setError(null);
    setAmount("");
    setTxHash(null);
  };

  if (!option) {
    return (
      <div className="p-6 bg-black/80 border border-gray-800 rounded-lg shadow-lg">
        <h2 className="text-xl font-light text-purple-300 mb-4">Redeem Pairs</h2>
        <div className="text-gray-400">Select an option to redeem</div>
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
    if (status === "working") return "Redeeming...";
    return "Redeem Pairs";
  };

  // Calculate max redeemable (minimum of both balances)
  const maxRedeemable =
    option.balances?.option && option.balances?.redemption
      ? option.balances.option < option.balances.redemption
        ? option.balances.option
        : option.balances.redemption
      : 0n;

  return (
    <div className="p-6 bg-black/80 border border-gray-800 rounded-lg shadow-lg">
      <h2 className="text-xl font-light text-purple-300 mb-4">Redeem Pairs</h2>

      {/* Balances */}
      <div className="space-y-2 mb-4">
        <div className="flex justify-between text-sm">
          <span className="text-gray-400">Option Balance</span>
          <span className="text-purple-300">{formatBalance(option.balances?.option, option.collateral.decimals)}</span>
        </div>
        <div className="flex justify-between text-sm">
          <span className="text-gray-400">Redemption Balance</span>
          <span className="text-purple-300">
            {formatBalance(option.balances?.redemption, option.collateral.decimals)}
          </span>
        </div>
        <div className="flex justify-between text-sm font-semibold">
          <span className="text-gray-400">Max Redeemable</span>
          <span className="text-purple-300">{formatBalance(maxRedeemable, option.collateral.decimals)}</span>
        </div>
        <div className="flex justify-between text-sm">
          <span className="text-gray-400">Collateral ({option.collateral.symbol})</span>
          <span className="text-purple-300">
            {formatBalance(option.balances?.collateral, option.collateral.decimals)}
          </span>
        </div>
      </div>

      {/* Info */}
      <div className="mb-4 p-3 bg-purple-900/20 rounded-lg text-xs text-purple-300 border border-purple-800">
        Burns Option + Redemption token pairs to get collateral back. No approvals needed.
      </div>

      {/* Amount Input */}
      <div className="mb-4">
        <div className="flex justify-between items-center mb-1">
          <label className="block text-sm text-gray-400">Amount (Pairs)</label>
          <button
            onClick={() => setAmount(formatUnits(maxRedeemable, 18))}
            className="text-xs text-purple-400 hover:text-purple-300 underline"
            disabled={status === "working" || maxRedeemable === 0n}
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
          ✓ Redeemed successfully!
        </div>
      )}

      {/* Action Button */}
      <button
        onClick={status === "success" ? handleReset : handleRedeem}
        disabled={
          status === "working" || !amount || parseFloat(amount) <= 0 || option.isExpired || maxRedeemable === 0n
        }
        className={`w-full py-2 px-4 rounded-lg transition-colors font-medium ${
          status === "working" || !amount || parseFloat(amount) <= 0 || option.isExpired || maxRedeemable === 0n
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

      {/* Warnings */}
      {option.isExpired && (
        <div className="mt-2 text-yellow-500 text-sm text-center p-2 bg-yellow-900/20 rounded border border-yellow-800">
          ⚠️ This option has expired
        </div>
      )}
      {maxRedeemable === 0n && !option.isExpired && (
        <div className="mt-2 text-yellow-500 text-sm text-center p-2 bg-yellow-900/20 rounded border border-yellow-800">
          ⚠️ You need both Option and Redemption tokens to redeem
        </div>
      )}
    </div>
  );
}

export default Redeem;
