import { useState, useEffect } from "react";
import { formatUnits, parseUnits } from "viem";
import { useAccount, useReadContract, useWriteContract, useWaitForTransactionReceipt, useChainId } from "wagmi";
import { useBebopQuote } from "../hooks/useBebopQuote";
import { useBebopTrade } from "../hooks/useBebopTrade";
import { useTokenMap } from "../../mint/hooks/useTokenMap";
import type { TradableOption } from "../hooks/useTradableOptions";

// ERC20 ABI for approve and allowance
const ERC20_ABI = [
  {
    name: "approve",
    type: "function",
    stateMutability: "nonpayable",
    inputs: [
      { name: "spender", type: "address" },
      { name: "amount", type: "uint256" },
    ],
    outputs: [{ type: "bool" }],
  },
  {
    name: "allowance",
    type: "function",
    stateMutability: "view",
    inputs: [
      { name: "owner", type: "address" },
      { name: "spender", type: "address" },
    ],
    outputs: [{ type: "uint256" }],
  },
] as const;

// Bebop Router addresses by chain ID
const BEBOP_ROUTER_ADDRESSES: Record<number, string> = {
  1: "0xbEbEbEb035351f58602E0C1C8B59ECBfF5d5f47b", // Ethereum Mainnet
  1301: "0xbEbEbEb035351f58602E0C1C8B59ECBfF5d5f47b", // Unichain Sepolia (verify this)
  11155111: "0xbEbEbEb035351f58602E0C1C8B59ECBfF5d5f47b", // Sepolia
};

interface TradePanelProps {
  selectedOption: {
    optionAddress: string;
    strike: bigint;
    expiration: bigint;
    isPut: boolean;
    collateralAddress: string;
    considerationAddress: string;
  };
  onClose: () => void;
}

export function TradePanel({ selectedOption, onClose }: TradePanelProps) {
  const [tradeType, setTradeType] = useState<"buy" | "sell">("buy");
  const [amount, setAmount] = useState<string>("1");
  const { allTokensMap } = useTokenMap();
  const { address: userAddress } = useAccount();
  const chainId = useChainId();

  // Get token info
  const optionToken = selectedOption.optionAddress;
  const paymentToken = selectedOption.isPut
    ? selectedOption.collateralAddress
    : selectedOption.considerationAddress;

  // Find token symbols
  const paymentTokenSymbol =
    Object.values(allTokensMap).find(t => t.address.toLowerCase() === paymentToken.toLowerCase())?.symbol || "TOKEN";

  // Determine buy/sell tokens for Bebop
  const buyToken = tradeType === "buy" ? optionToken : paymentToken;
  const sellToken = tradeType === "buy" ? paymentToken : optionToken;

  // Parse amount (assume 18 decimals for option tokens)
  const sellAmount = amount ? parseUnits(amount, 18).toString() : "0";

  // Get Bebop router address for current chain
  const bebopRouter = BEBOP_ROUTER_ADDRESSES[chainId];

  // Fetch quote from Bebop
  const { data: quote, isLoading: quoteLoading, error: quoteError } = useBebopQuote({
    buyToken,
    sellToken,
    sellAmount,
    enabled: amount !== "" && parseFloat(amount) > 0,
  });

  // Check current allowance
  const { data: currentAllowance, refetch: refetchAllowance } = useReadContract({
    address: optionToken as `0x${string}`,
    abi: ERC20_ABI,
    functionName: "allowance",
    args: userAddress && bebopRouter ? [userAddress, bebopRouter as `0x${string}`] : undefined,
    query: {
      enabled: !!userAddress && !!bebopRouter,
    },
  });

  // Approval transaction
  const { writeContract: approve, data: approvalHash, isPending: isApproving } = useWriteContract();
  const { isSuccess: isApprovalSuccess } = useWaitForTransactionReceipt({
    hash: approvalHash,
  });

  // Refetch allowance after successful approval
  useEffect(() => {
    if (isApprovalSuccess) {
      refetchAllowance();
    }
  }, [isApprovalSuccess, refetchAllowance]);

  // Check if approval is needed
  const sellAmountBigInt = amount ? parseUnits(amount, 18) : 0n;
  const needsApproval = Boolean(
    tradeType === "sell" &&
    bebopRouter &&
    currentAllowance !== undefined &&
    currentAllowance < sellAmountBigInt
  );

  // Handle approval
  const handleApprove = async () => {
    if (!bebopRouter) return;

    try {
      approve({
        address: optionToken as `0x${string}`,
        abi: ERC20_ABI,
        functionName: "approve",
        args: [bebopRouter as `0x${string}`, sellAmountBigInt],
      });
    } catch (err) {
      console.error("Approval failed:", err);
    }
  };

  // Trade execution
  const { executeTrade, status, error: tradeError, txHash, reset } = useBebopTrade();

  // Reset trade status when option or trade type changes
  useEffect(() => {
    reset();
  }, [selectedOption, tradeType, reset]);

  const handleExecuteTrade = async () => {
    if (!quote) return;

    try {
      await executeTrade(quote);
    } catch (err) {
      console.error("Trade failed:", err);
    }
  };

  // Format dates
  const expirationDate = new Date(Number(selectedOption.expiration) * 1000);
  const strikeFormatted = formatUnits(selectedOption.strike, 18);

  return (
    <div className="p-6 bg-black/80 border border-gray-800 rounded-lg shadow-lg">
      <div className="flex justify-between items-center mb-4">
        <h2 className="text-xl font-light text-blue-300">Trade Option</h2>
        <button onClick={onClose} className="text-gray-400 hover:text-gray-200">
          ✕
        </button>
      </div>

      {/* Option Details */}
      <div className="mb-6 p-4 bg-gray-900 rounded-lg border border-gray-700">
        <div className="grid grid-cols-2 gap-3 text-sm">
          <div>
            <div className="text-gray-400">Type</div>
            <div className="text-blue-300 font-medium">{selectedOption.isPut ? "PUT" : "CALL"}</div>
          </div>
          <div>
            <div className="text-gray-400">Strike</div>
            <div className="text-blue-300 font-medium">${strikeFormatted}</div>
          </div>
          <div className="col-span-2">
            <div className="text-gray-400">Expiration</div>
            <div className="text-blue-300 font-medium">
              {expirationDate.toLocaleDateString()} {expirationDate.toLocaleTimeString()}
            </div>
          </div>
        </div>
      </div>

      {/* Trade Type Selector */}
      <div className="mb-4">
        <div className="text-gray-400 mb-2 text-sm">Action</div>
        <div className="flex gap-2">
          <button
            onClick={() => setTradeType("buy")}
            className={`flex-1 py-2 px-4 rounded-lg transition-colors ${
              tradeType === "buy"
                ? "bg-green-500 text-white"
                : "bg-gray-900 text-gray-400 border border-gray-700 hover:border-green-500"
            }`}
          >
            Buy
          </button>
          <button
            onClick={() => setTradeType("sell")}
            className={`flex-1 py-2 px-4 rounded-lg transition-colors ${
              tradeType === "sell"
                ? "bg-red-500 text-white"
                : "bg-gray-900 text-gray-400 border border-gray-700 hover:border-red-500"
            }`}
          >
            Sell
          </button>
        </div>
      </div>

      {/* Amount Input */}
      <div className="mb-4">
        <label className="block text-gray-400 mb-2 text-sm">
          Amount {tradeType === "buy" ? "to buy" : "to sell"}
        </label>
        <input
          type="number"
          value={amount}
          onChange={e => setAmount(e.target.value)}
          placeholder="0.0"
          step="0.01"
          min="0"
          className="w-full p-3 rounded-lg border border-gray-700 bg-black/60 text-blue-300 focus:outline-none focus:border-blue-500"
        />
      </div>

      {/* Token Approval Section */}
      <div className="mb-4 p-4 bg-gray-900 rounded-lg border border-gray-700">
        <h3 className="text-sm font-medium text-gray-300 mb-3">Token Allowance</h3>
        <div className="space-y-3">
          {!bebopRouter ? (
            <div className="p-3 bg-red-900/20 rounded border border-red-700">
              <div className="text-red-300 text-sm">
                Bebop router not available for chain {chainId}
              </div>
            </div>
          ) : (
            <>
              <div className="flex justify-between items-center text-sm">
                <span className="text-gray-400">Current Allowance:</span>
                <span className="text-blue-300 font-mono">
                  {currentAllowance !== undefined ? formatUnits(currentAllowance, 18) : "Loading..."}
                </span>
              </div>
              <div className="flex justify-between items-center text-sm">
                <span className="text-gray-400">Bebop Router:</span>
                <span className="text-blue-300 font-mono text-xs">
                  {bebopRouter.slice(0, 6)}...{bebopRouter.slice(-4)}
                </span>
              </div>
              <button
                onClick={handleApprove}
                disabled={isApproving}
                className={`w-full py-2.5 px-4 rounded-lg font-medium transition-colors ${
                  isApproving
                    ? "bg-gray-800 text-gray-500 cursor-not-allowed"
                    : "bg-blue-500 hover:bg-blue-600 text-white"
                }`}
              >
                {isApproving ? "Approving..." : "Approve Spending"}
              </button>
            </>
          )}
          {isApprovalSuccess && (
            <div className="p-3 bg-green-900/20 rounded border border-green-700">
              <div className="text-green-300 text-sm">Approval successful!</div>
              {approvalHash && (
                <div className="mt-1 text-xs text-gray-400 break-all">
                  Tx: {approvalHash}
                </div>
              )}
            </div>
          )}
        </div>
      </div>

      {/* Quote Display */}
      {quoteLoading && (
        <div className="mb-4 p-4 bg-gray-900 rounded-lg border border-gray-700">
          <div className="text-blue-300">Fetching quote...</div>
        </div>
      )}

      {quoteError && (
        <div className="mb-4 p-4 bg-red-900/20 rounded-lg border border-red-700">
          <div className="text-red-300">Error: {quoteError.message}</div>
        </div>
      )}

      {quote && !quoteLoading && (
        <div className="mb-4 p-4 bg-gray-900 rounded-lg border border-gray-700">
          <div className="text-sm space-y-2">
            <div className="flex justify-between">
              <span className="text-gray-400">You pay:</span>
              <span className="text-blue-300 font-medium">
                {quote.sellAmount ? formatUnits(BigInt(quote.sellAmount), 18) : "N/A"} {tradeType === "buy" ? paymentTokenSymbol : "OPT"}
              </span>
            </div>
            <div className="flex justify-between">
              <span className="text-gray-400">You receive:</span>
              <span className="text-blue-300 font-medium">
                {quote.buyAmount ? formatUnits(BigInt(quote.buyAmount), 18) : "N/A"} {tradeType === "buy" ? "OPT" : paymentTokenSymbol}
              </span>
            </div>
            {quote.price && (
              <div className="flex justify-between">
                <span className="text-gray-400">Price:</span>
                <span className="text-blue-300 font-medium">{quote.price}</span>
              </div>
            )}
            {quote.estimatedGas && (
              <div className="flex justify-between">
                <span className="text-gray-400">Est. Gas:</span>
                <span className="text-blue-300 font-medium">{quote.estimatedGas}</span>
              </div>
            )}
          </div>
          <div className="mt-2 text-xs text-gray-500">Quote refreshes every 15 seconds</div>
          {/* Debug info */}
          <details className="mt-2">
            <summary className="text-xs text-gray-500 cursor-pointer">Debug: Show raw quote data</summary>
            <div className="mt-1 text-xs text-gray-600 break-all bg-black/40 p-2 rounded">
              <pre>{JSON.stringify(quote, null, 2)}</pre>
            </div>
          </details>
        </div>
      )}

      {/* Transaction Status */}
      {status !== "idle" && (
        <div
          className={`mb-4 p-4 rounded-lg border ${
            status === "success"
              ? "bg-green-900/20 border-green-700"
              : status === "error"
                ? "bg-red-900/20 border-red-700"
                : "bg-blue-900/20 border-blue-700"
          }`}
        >
          <div className={status === "success" ? "text-green-300" : status === "error" ? "text-red-300" : "text-blue-300"}>
            {status === "preparing" && "Preparing transaction..."}
            {status === "pending" && "Transaction pending..."}
            {status === "success" && "Trade successful!"}
            {status === "error" && `Error: ${tradeError}`}
          </div>
          {txHash && (
            <div className="mt-2 text-xs text-gray-400 break-all">
              Tx: {txHash}
            </div>
          )}
        </div>
      )}

      {/* Execute Button */}
      <button
        onClick={handleExecuteTrade}
        disabled={!quote || status === "pending" || status === "preparing" || needsApproval}
        className={`w-full py-3 px-4 rounded-lg font-medium transition-colors ${
          !quote || status === "pending" || status === "preparing" || needsApproval
            ? "bg-gray-800 text-gray-500 cursor-not-allowed"
            : tradeType === "buy"
              ? "bg-green-500 hover:bg-green-600 text-white"
              : "bg-red-500 hover:bg-red-600 text-white"
        }`}
      >
        {status === "pending" || status === "preparing"
          ? "Processing..."
          : needsApproval
            ? "Approval Required"
            : tradeType === "buy"
              ? "Buy Option"
              : "Sell Option"}
      </button>
    </div>
  );
}
