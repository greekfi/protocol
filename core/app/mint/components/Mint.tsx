import { useState } from "react";
import { useApproveERC20 } from "../hooks/transactions/useApproveERC20";
import { useApproveFactory } from "../hooks/transactions/useApproveFactory";
import { useMintTransaction } from "../hooks/transactions/useMintTransaction";
import { useAllowances } from "../hooks/useAllowances";
import { useContracts } from "../hooks/useContracts";
import { useOption } from "../hooks/useOption";
import { Address, formatUnits, parseUnits } from "viem";
import { useWaitForTransactionReceipt } from "wagmi";

interface MintActionCleanProps {
  optionAddress: Address | undefined;
}

/**
 * Clean mint component - all logic lives here, hooks are just data/transactions
 */
export function Mint({ optionAddress }: MintActionCleanProps) {
  const [amount, setAmount] = useState("");
  const [txHash, setTxHash] = useState<`0x${string}` | null>(null);
  const [status, setStatus] = useState<"idle" | "working" | "success" | "error">("idle");
  const [error, setError] = useState<string | null>(null);

  // Data fetching (pure reads)
  const { data: option, refetch: refetchOption } = useOption(optionAddress);
  const factoryAddress = useContracts()?.OptionFactory?.address;
  const amountWei = amount ? parseUnits(amount, option?.collateral.decimals ?? 18) : 0n;
  const allowances = useAllowances(option?.collateral.address_, amountWei);

  // Transaction executors (pure writes)
  const approveERC20 = useApproveERC20();
  const approveFactory = useApproveFactory();
  const mintTx = useMintTransaction();

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
      allowances.refetch();
    }
  }

  if (txHash && txFailed) {
    setTxHash(null);
    setStatus("error");
    setError("Transaction failed");
  }

  const handleMint = async () => {
    if (!optionAddress || !option || !factoryAddress) return;
    if (!amount || parseFloat(amount) <= 0) return;

    try {
      setStatus("working");
      setError(null);

      const wei = parseUnits(amount, option.collateral.decimals);

      // Refetch allowances
      await allowances.refetch();

      // Step 1: Approve ERC20 if needed
      if (allowances.needsErc20Approval) {
        console.log("=== ERC20 Approve Debug ===");
        console.log("Token address:", option.collateral.address_);
        console.log("Factory address:", factoryAddress);
        console.log("Token symbol:", option.collateral.symbol);
        console.log("Amount needed:", wei.toString());

        try {
          const hash = await approveERC20.approve(option.collateral.address_, factoryAddress);
          console.log("Approval tx hash:", hash);
          setTxHash(hash);
          // Wait for this component to re-render when txConfirmed updates
          return;
        } catch (err: any) {
          console.error("ERC20 Approve failed:", err);
          throw err;
        }
      }

      // Step 2: Approve factory if needed
      if (allowances.needsFactoryApproval) {
        const hash = await approveFactory.approve(option.collateral.address_);
        setTxHash(hash);
        return;
      }

      // Step 3: Mint
      const hash = await mintTx.mint(optionAddress, wei);
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
        <h2 className="text-xl font-light text-blue-300 mb-4">Mint Options</h2>
        <div className="text-gray-400">Select an option to mint</div>
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
    if (status === "working") {
      if (allowances.needsErc20Approval) return "Approving token...";
      if (allowances.needsFactoryApproval) return "Approving factory...";
      return "Minting...";
    }
    // Idle state - show what action will be taken
    if (allowances.needsErc20Approval) return "Approve Token";
    if (allowances.needsFactoryApproval) return "Approve Factory";
    return "Mint Options";
  };

  return (
    <div className="p-6 bg-black/80 border border-gray-800 rounded-lg shadow-lg">
      <h2 className="text-xl font-light text-blue-300 mb-4">Mint Options</h2>

      {/* Balances */}
      <div className="space-y-2 mb-4">
        <div className="flex justify-between text-sm">
          <span className="text-gray-400">Collateral ({option.collateral.symbol})</span>
          <span className="text-blue-300">
            {formatBalance(option.balances?.collateral, option.collateral.decimals)}
          </span>
        </div>
        <div className="flex justify-between text-sm">
          <span className="text-gray-400">Option Balance</span>
          <span className="text-blue-300">{formatBalance(option.balances?.option, option.collateral.decimals)}</span>
        </div>
        <div className="flex justify-between text-sm">
          <span className="text-gray-400">Redemption Balance</span>
          <span className="text-blue-300">
            {formatBalance(option.balances?.redemption, option.collateral.decimals)}
          </span>
        </div>
      </div>

      {/* Approval Status - only show when working */}
      {status === "working" && (
        <div className="mb-4 p-3 bg-gray-900 rounded-lg text-xs space-y-1">
          <div className="font-semibold text-gray-300 mb-2">Approval Status:</div>
          <div className="flex justify-between items-center">
            <span className="text-gray-400">Token → Factory:</span>
            <span className={allowances.needsErc20Approval ? "text-yellow-500" : "text-green-500"}>
              {allowances.needsErc20Approval ? "⏳ Pending" : "✓ Approved"}
            </span>
          </div>
          <div className="flex justify-between items-center">
            <span className="text-gray-400">Factory → Token:</span>
            <span className={allowances.needsFactoryApproval ? "text-yellow-500" : "text-green-500"}>
              {allowances.needsFactoryApproval ? "⏳ Pending" : "✓ Approved"}
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
          ✓ Minted successfully!
        </div>
      )}

      {/* Action Button */}
      <button
        onClick={status === "success" ? handleReset : handleMint}
        disabled={status === "working" || !amount || parseFloat(amount) <= 0 || option.isExpired}
        className={`w-full py-2 px-4 rounded-lg transition-colors font-medium ${
          status === "working" || !amount || parseFloat(amount) <= 0 || option.isExpired
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

      {/* Expired Warning */}
      {option.isExpired && (
        <div className="mt-2 text-yellow-500 text-sm text-center p-2 bg-yellow-900/20 rounded border border-yellow-800">
          ⚠️ This option has expired
        </div>
      )}
    </div>
  );
}

export default Mint;
