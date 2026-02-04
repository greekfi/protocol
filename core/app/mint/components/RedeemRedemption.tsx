import { useState } from "react";
import { useRedeemRedemption } from "../hooks/transactions/useRedeemRedemption";
import { useOption } from "../hooks/useOption";
import { Address, erc20Abi, formatUnits, parseUnits } from "viem";
import { useReadContract, useWaitForTransactionReceipt } from "wagmi";

interface RedeemRedemptionProps {
  optionAddress: Address | undefined;
}

/**
 * Redeem Redemption tokens after expiration
 * Burns Redemption tokens to get collateral or consideration back
 */
export function RedeemRedemption({ optionAddress }: RedeemRedemptionProps) {
  const [amount, setAmount] = useState("");
  const [txHash, setTxHash] = useState<`0x${string}` | null>(null);
  const [status, setStatus] = useState<"idle" | "working" | "success" | "error">("idle");
  const [error, setError] = useState<string | null>(null);
  const [redeemForConsideration, setRedeemForConsideration] = useState(false);

  // Data fetching
  const { data: option, refetch: refetchOption } = useOption(optionAddress);

  // Get consideration balance of the Redemption contract
  const { data: redemptionConsiderationBalance } = useReadContract({
    address: option?.consideration.address_,
    abi: erc20Abi,
    functionName: "balanceOf",
    args: option?.redemption ? [option.redemption] : undefined,
    query: { enabled: Boolean(option?.consideration.address_ && option?.redemption) },
  });

  // Transaction executor
  const redeemTx = useRedeemRedemption();

  // Debug render
  console.log("=== RedeemRedemption Render ===");
  console.log("optionAddress:", optionAddress);
  console.log("option:", option);
  console.log("redemptionConsiderationBalance:", redemptionConsiderationBalance?.toString());
  console.log("status:", status);
  console.log("txHash:", txHash);

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
    if (!optionAddress || !option) {
      console.log("=== RedeemRedemption: Missing data ===");
      console.log("optionAddress:", optionAddress);
      console.log("option:", option);
      return;
    }
    if (!amount || parseFloat(amount) <= 0) {
      console.log("=== RedeemRedemption: Invalid amount ===");
      console.log("amount:", amount);
      return;
    }

    try {
      setStatus("working");
      setError(null);

      const wei = parseUnits(amount, 18); // Redemption tokens are 18 decimals

      console.log("=== RedeemRedemption Debug ===");
      console.log("Amount entered:", amount);
      console.log("Amount in wei:", wei.toString());
      console.log("Redemption balance:", option.balances?.redemption?.toString());
      console.log("Redemption address:", option.redemption);
      console.log("Redeem for consideration:", redeemForConsideration);
      console.log("Is expired:", option.isExpired);
      console.log("Consideration balance:", redemptionConsiderationBalance?.toString());

      // Check balance
      if (option.balances?.redemption && option.balances.redemption < wei) {
        console.error("Failed: Insufficient Redemption balance");
        setError("Insufficient Redemption token balance");
        setStatus("error");
        return;
      }

      // Call appropriate redeem function
      // If not expired, MUST use redeemConsideration (redeem() requires expiration)
      const shouldUseConsideration = redeemForConsideration || !option.isExpired;

      console.log("Calling redeem function...");
      console.log("shouldUseConsideration:", shouldUseConsideration);
      const hash = shouldUseConsideration
        ? await redeemTx.redeemConsideration(option.redemption, wei)
        : await redeemTx.redeem(option.redemption, wei);
      console.log("Transaction hash:", hash);
      setTxHash(hash);
    } catch (err: any) {
      console.error("=== RedeemRedemption Error ===");
      console.error("Error:", err);
      console.error("Error message:", err.message);
      console.error("Error stack:", err.stack);
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
        <h2 className="text-xl font-light text-orange-300 mb-4">Redeem After Expiration</h2>
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
    return "Redeem Redemptions";
  };

  // Check if redemption is available (expired OR has consideration balance)
  const hasConsiderationBalance = (redemptionConsiderationBalance ?? 0n) > 0n;
  const canRedeem = option.isExpired || hasConsiderationBalance;

  return (
    <div className="p-6 bg-black/80 border border-gray-800 rounded-lg shadow-lg">
      <h2 className="text-xl font-light text-orange-300 mb-4">Redeem Redemptions</h2>

      {/* Balances */}
      <div className="space-y-2 mb-4">
        <div className="flex justify-between text-sm">
          <span className="text-gray-400">Your Redemption Balance</span>
          <span className="text-orange-300">
            {formatBalance(option.balances?.redemption, option.collateral.decimals)}
          </span>
        </div>
        <div className="flex justify-between text-sm">
          <span className="text-gray-400">Your Collateral ({option.collateral.symbol})</span>
          <span className="text-orange-300">
            {formatBalance(option.balances?.collateral, option.collateral.decimals)}
          </span>
        </div>
        {hasConsiderationBalance && (
          <div className="flex justify-between text-sm">
            <span className="text-gray-400">Contract {option.consideration.symbol} Balance</span>
            <span className="text-orange-300">
              {formatBalance(redemptionConsiderationBalance, option.consideration.decimals)}
            </span>
          </div>
        )}
      </div>

      {/* Info */}
      <div className="mb-4 p-3 bg-orange-900/20 rounded-lg text-xs text-orange-300 border border-orange-800">
        {option.isExpired && hasConsiderationBalance
          ? "Burns Redemption tokens to get collateral or consideration back. Choose below."
          : option.isExpired
            ? "Burns Redemption tokens to get collateral back (post-expiration)."
            : hasConsiderationBalance
              ? `⚠️ NOT EXPIRED: Will redeem for ${option.consideration.symbol} (consideration) since collateral redemption requires expiration.`
              : "⚠️ This option has not expired yet and has no consideration balance. Use 'Redeem Pairs' component instead."}
      </div>

      {/* Checkbox for choosing consideration (only show if expired AND has consideration) */}
      {option.isExpired && hasConsiderationBalance && (
        <div className="mb-4">
          <label className="flex items-center space-x-2 cursor-pointer">
            <input
              type="checkbox"
              checked={redeemForConsideration}
              onChange={e => setRedeemForConsideration(e.target.checked)}
              disabled={status === "working"}
              className="w-4 h-4 text-orange-500 bg-gray-700 border-gray-600 rounded focus:ring-orange-500"
            />
            <span className="text-sm text-gray-300">
              Redeem for {option.consideration.symbol} instead of {option.collateral.symbol}
            </span>
          </label>
        </div>
      )}

      {/* Amount Input */}
      <div className="mb-4">
        <div className="flex justify-between items-center mb-1">
          <label className="block text-sm text-gray-400">Amount</label>
          <button
            onClick={() => setAmount(formatUnits(option.balances?.redemption ?? 0n, 18))}
            className="text-xs text-orange-400 hover:text-orange-300 underline"
            disabled={status === "working" || !canRedeem}
          >
            Max
          </button>
        </div>
        <input
          type="number"
          value={amount}
          onChange={e => setAmount(e.target.value)}
          placeholder="0.0"
          className="w-full p-2 rounded-lg border border-gray-700 bg-black/60 text-orange-300"
          disabled={status === "working" || !canRedeem}
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
          status === "working" ||
          !amount ||
          parseFloat(amount) <= 0 ||
          !canRedeem ||
          (option.balances?.redemption ?? 0n) === 0n
        }
        className={`w-full py-2 px-4 rounded-lg transition-colors font-medium ${
          status === "working" ||
          !amount ||
          parseFloat(amount) <= 0 ||
          !canRedeem ||
          (option.balances?.redemption ?? 0n) === 0n
            ? "bg-gray-600 cursor-not-allowed text-gray-400"
            : status === "success"
              ? "bg-green-600 hover:bg-green-700 text-white"
              : status === "error"
                ? "bg-red-600 hover:bg-red-700 text-white"
                : "bg-orange-500 hover:bg-orange-600 text-white"
        }`}
      >
        {getStatusText()}
      </button>

      {/* Warnings */}
      {!canRedeem && (
        <div className="mt-2 text-yellow-500 text-sm text-center p-2 bg-yellow-900/20 rounded border border-yellow-800">
          Option has not expired yet and has no consideration balance. Use Redeem Pairs component.
        </div>
      )}
      {canRedeem && (option.balances?.redemption ?? 0n) === 0n && (
        <div className="mt-2 text-yellow-500 text-sm text-center p-2 bg-yellow-900/20 rounded border border-yellow-800">
          You have no Redemption tokens to redeem
        </div>
      )}
    </div>
  );
}

export default RedeemRedemption;
