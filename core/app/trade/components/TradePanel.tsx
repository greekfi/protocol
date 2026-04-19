import { useEffect, useState } from "react";
import { useTokenMap } from "../../mint/hooks/useTokenMap";
import { useBebopQuote } from "../hooks/useBebopQuote";
import { useBebopTrade } from "../hooks/useBebopTrade";
import { formatUnits, parseUnits } from "viem";
import { useAccount, useChainId, useReadContract, useWaitForTransactionReceipt, useWriteContract } from "wagmi";

// ERC20 ABI for approve, allowance, and decimals
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
  {
    name: "decimals",
    type: "function",
    stateMutability: "view",
    inputs: [],
    outputs: [{ type: "uint8" }],
  },
] as const;

// Bebop Router addresses by chain ID
const BEBOP_ROUTER_ADDRESSES: Record<number, string> = {
  1: "0xbbbbbBB520d69a9775E85b458C58c648259FAD5F", // Ethereum Mainnet
  1301: "0xbbbbbBB520d69a9775E85b458C58c648259FAD5F", // Unichain Sepolia (verify this)
  11155111: "0xbbbbbBB520d69a9775E85b458C58c648259FAD5F", // Sepolia
};

interface TradePanelProps {
  selectedOption: {
    optionAddress: string;
    strike: bigint;
    expiration: bigint;
    isPut: boolean;
    collateralAddress: string;
    considerationAddress: string;
    isBuy: boolean;
  };
  onClose: () => void;
}

export function TradePanel({ selectedOption, onClose }: TradePanelProps) {
  const [isBuy, setIsBuy] = useState<boolean>(selectedOption.isBuy);

  // Update isBuy when selectedOption changes
  useEffect(() => {
    setIsBuy(selectedOption.isBuy);
  }, [selectedOption.isBuy]);
  const [amount, setAmount] = useState<string>("1");
  const { allTokensMap } = useTokenMap();
  const { address: userAddress } = useAccount();
  const chainId = useChainId();

  // Get token info
  const optionToken = selectedOption.optionAddress;

  // Payment token is USDC based on chain
  const USDC_ADDRESSES: Record<number, string> = {
    1: "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48", // Ethereum Mainnet
    130: "0x078d782b760474a361dda0af3839290b0ef57ad6", // Unichain (chain 130)
    1301: "0x078d782b760474a361dda0af3839290b0ef57ad6", // Unichain Sepolia
    11155111: "0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238", // Sepolia
    8453: "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913", // Base
  };

  const paymentToken = USDC_ADDRESSES[chainId] || USDC_ADDRESSES[1];

  // Find token symbols
  const paymentTokenSymbol =
    Object.values(allTokensMap).find(t => t.address.toLowerCase() === paymentToken.toLowerCase())?.symbol || "USDC";

  // Determine buy/sell tokens for Bebop
  const buyToken = isBuy ? optionToken : paymentToken;
  const sellToken = isBuy ? paymentToken : optionToken;

  // Fetch decimals for buy token
  const { data: buyTokenDecimalsData } = useReadContract({
    address: buyToken as `0x${string}`,
    abi: ERC20_ABI,
    functionName: "decimals",
  });

  // Fetch decimals for sell token
  const { data: sellTokenDecimalsData } = useReadContract({
    address: sellToken as `0x${string}`,
    abi: ERC20_ABI,
    functionName: "decimals",
  });

  // Use fetched decimals or default to 18 if not available yet
  const buyTokenDecimals = buyTokenDecimalsData ?? 18;
  const sellTokenDecimals = sellTokenDecimalsData ?? 18;

  // Use buy_amounts when buying options (user wants X options, Bebop tells us the USDC cost)
  // Use sell_amounts when selling options (user has X options to sell, Bebop tells us the USDC received)
  const buyAmount = isBuy && amount ? parseUnits(amount, buyTokenDecimals).toString() : undefined;
  const sellAmount = !isBuy && amount ? parseUnits(amount, sellTokenDecimals).toString() : undefined;

  // Get Bebop router address for current chain
  const bebopRouter = BEBOP_ROUTER_ADDRESSES[chainId];

  // Fetch quote from Bebop
  const {
    data: quote,
    isLoading: quoteLoading,
    error: quoteError,
  } = useBebopQuote({
    buyToken,
    sellToken,
    buyAmount,
    sellAmount,
    enabled: amount !== "" && parseFloat(amount) > 0,
  });

  // Check USDC allowance
  const { data: usdcAllowance, refetch: refetchUsdcAllowance } = useReadContract({
    address: paymentToken as `0x${string}`,
    abi: ERC20_ABI,
    functionName: "allowance",
    args: userAddress && bebopRouter ? [userAddress, bebopRouter as `0x${string}`] : undefined,
    query: {
      enabled: !!userAddress && !!bebopRouter,
    },
  });

  // Check option token allowance
  const { data: optionAllowance, refetch: refetchOptionAllowance } = useReadContract({
    address: optionToken as `0x${string}`,
    abi: ERC20_ABI,
    functionName: "allowance",
    args: userAddress && bebopRouter ? [userAddress, bebopRouter as `0x${string}`] : undefined,
    query: {
      enabled: !!userAddress && !!bebopRouter,
    },
  });

  // USDC approval transaction
  const { writeContract: approveUsdc, data: usdcApprovalHash, isPending: isApprovingUsdc } = useWriteContract();
  const { isSuccess: isUsdcApprovalSuccess } = useWaitForTransactionReceipt({
    hash: usdcApprovalHash,
  });

  // Option approval transaction
  const { writeContract: approveOption, data: optionApprovalHash, isPending: isApprovingOption } = useWriteContract();
  const { isSuccess: isOptionApprovalSuccess } = useWaitForTransactionReceipt({
    hash: optionApprovalHash,
  });

  // Refetch allowances after successful approvals
  useEffect(() => {
    if (isUsdcApprovalSuccess) {
      refetchUsdcAllowance();
    }
  }, [isUsdcApprovalSuccess, refetchUsdcAllowance]);

  useEffect(() => {
    if (isOptionApprovalSuccess) {
      refetchOptionAllowance();
    }
  }, [isOptionApprovalSuccess, refetchOptionAllowance]);

  // Check if USDC approval is needed (when buying options)
  const usdcNeededAmount = isBuy && quote?.sellAmount ? BigInt(quote.sellAmount) : 0n;
  const needsUsdcApproval = Boolean(
    bebopRouter && usdcAllowance !== undefined && usdcNeededAmount > 0n && usdcAllowance < usdcNeededAmount,
  );

  // Check if option approval is needed (when selling options)
  const optionNeededAmount = !isBuy && amount ? parseUnits(amount, sellTokenDecimals) : 0n;
  const needsOptionApproval = Boolean(
    bebopRouter && optionAllowance !== undefined && optionNeededAmount > 0n && optionAllowance < optionNeededAmount,
  );

  // Handle USDC approval (approve max amount for convenience)
  const handleApproveUsdc = async () => {
    if (!bebopRouter) return;

    try {
      approveUsdc({
        address: paymentToken as `0x${string}`,
        abi: ERC20_ABI,
        functionName: "approve",
        args: [
          bebopRouter as `0x${string}`,
          BigInt("0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"),
        ], // max uint256
      });
    } catch (err) {
      console.error("USDC approval failed:", err);
    }
  };

  // Handle option token approval (approve max amount for convenience)
  const handleApproveOption = async () => {
    if (!bebopRouter) return;

    try {
      approveOption({
        address: optionToken as `0x${string}`,
        abi: ERC20_ABI,
        functionName: "approve",
        args: [
          bebopRouter as `0x${string}`,
          BigInt("0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"),
        ], // max uint256
      });
    } catch (err) {
      console.error("Option approval failed:", err);
    }
  };

  // Trade execution
  const { executeTrade, status, error: tradeError, txHash, reset } = useBebopTrade();

  // Reset trade status when option or trade type changes
  useEffect(() => {
    reset();
  }, [selectedOption, isBuy, reset]);

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
            onClick={() => setIsBuy(true)}
            className={`flex-1 py-2 px-4 rounded-lg transition-colors ${
              isBuy
                ? "bg-green-500 text-white"
                : "bg-gray-900 text-gray-400 border border-gray-700 hover:border-green-500"
            }`}
          >
            Buy
          </button>
          <button
            onClick={() => setIsBuy(false)}
            className={`flex-1 py-2 px-4 rounded-lg transition-colors ${
              !isBuy ? "bg-red-500 text-white" : "bg-gray-900 text-gray-400 border border-gray-700 hover:border-red-500"
            }`}
          >
            Sell
          </button>
        </div>
      </div>

      {/* Amount Input */}
      <div className="mb-4">
        <label className="block text-gray-400 mb-2 text-sm">Amount {isBuy ? "to buy" : "to sell"}</label>
        <input
          type="number"
          value={amount}
          onChange={e => setAmount(e.target.value)}
          placeholder="0.0"
          step="any"
          min="0"
          className="w-full p-3 rounded-lg border border-gray-700 bg-black/60 text-blue-300 focus:outline-none focus:border-blue-500"
        />
      </div>

      {/* Token Approval Sections */}
      {!bebopRouter ? (
        <div className="mb-4 p-4 bg-red-900/20 rounded-lg border border-red-700">
          <div className="text-red-300 text-sm">Bebop router not available for chain {chainId}</div>
        </div>
      ) : (
        <div className="mb-4 space-y-3">
          {/* USDC Approval */}
          <div className="p-4 bg-gray-900 rounded-lg border border-gray-700">
            <h3 className="text-sm font-medium text-gray-300 mb-3">USDC Allowance</h3>
            <div className="space-y-3">
              <div className="flex justify-between items-center text-sm">
                <span className="text-gray-400">Current Allowance:</span>
                <span className="text-blue-300 font-mono">
                  {usdcAllowance !== undefined ? formatUnits(usdcAllowance, 6) : "Loading..."}
                </span>
              </div>
              <div className="flex justify-between items-center text-sm">
                <span className="text-gray-400">Bebop Router:</span>
                <span className="text-blue-300 font-mono text-xs">
                  {bebopRouter.slice(0, 6)}...{bebopRouter.slice(-4)}
                </span>
              </div>
              <button
                onClick={handleApproveUsdc}
                disabled={isApprovingUsdc}
                className={`w-full py-2.5 px-4 rounded-lg font-medium transition-colors ${
                  isApprovingUsdc
                    ? "bg-gray-800 text-gray-500 cursor-not-allowed"
                    : "bg-blue-500 hover:bg-blue-600 text-white"
                }`}
              >
                {isApprovingUsdc ? "Approving..." : "Approve USDC"}
              </button>
              {isUsdcApprovalSuccess && (
                <div className="p-3 bg-green-900/20 rounded border border-green-700">
                  <div className="text-green-300 text-sm">USDC approval successful!</div>
                  {usdcApprovalHash && (
                    <div className="mt-1 text-xs text-gray-400 break-all">Tx: {usdcApprovalHash}</div>
                  )}
                </div>
              )}
            </div>
          </div>

          {/* Option Token Approval */}
          <div className="p-4 bg-gray-900 rounded-lg border border-gray-700">
            <h3 className="text-sm font-medium text-gray-300 mb-3">Option Token Allowance</h3>
            <div className="space-y-3">
              <div className="flex justify-between items-center text-sm">
                <span className="text-gray-400">Current Allowance:</span>
                <span className="text-blue-300 font-mono">
                  {optionAllowance !== undefined ? formatUnits(optionAllowance, buyTokenDecimals) : "Loading..."}
                </span>
              </div>
              <div className="flex justify-between items-center text-sm">
                <span className="text-gray-400">Bebop Router:</span>
                <span className="text-blue-300 font-mono text-xs">
                  {bebopRouter.slice(0, 6)}...{bebopRouter.slice(-4)}
                </span>
              </div>
              <button
                onClick={handleApproveOption}
                disabled={isApprovingOption}
                className={`w-full py-2.5 px-4 rounded-lg font-medium transition-colors ${
                  isApprovingOption
                    ? "bg-gray-800 text-gray-500 cursor-not-allowed"
                    : "bg-blue-500 hover:bg-blue-600 text-white"
                }`}
              >
                {isApprovingOption ? "Approving..." : "Approve Option Token"}
              </button>
              {isOptionApprovalSuccess && (
                <div className="p-3 bg-green-900/20 rounded border border-green-700">
                  <div className="text-green-300 text-sm">Option approval successful!</div>
                  {optionApprovalHash && (
                    <div className="mt-1 text-xs text-gray-400 break-all">Tx: {optionApprovalHash}</div>
                  )}
                </div>
              )}
            </div>
          </div>
        </div>
      )}

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
                {quote.sellAmount ? formatUnits(BigInt(quote.sellAmount), sellTokenDecimals) : "N/A"}{" "}
                {isBuy ? paymentTokenSymbol : "OPT"}
              </span>
            </div>
            <div className="flex justify-between">
              <span className="text-gray-400">You receive:</span>
              <span className="text-blue-300 font-medium">
                {quote.buyAmount ? formatUnits(BigInt(quote.buyAmount), buyTokenDecimals) : "N/A"}{" "}
                {isBuy ? "OPT" : paymentTokenSymbol}
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
          <div
            className={status === "success" ? "text-green-300" : status === "error" ? "text-red-300" : "text-blue-300"}
          >
            {status === "preparing" && "Preparing transaction..."}
            {status === "pending" && "Transaction pending..."}
            {status === "success" && "Trade successful!"}
            {status === "error" && `Error: ${tradeError}`}
          </div>
          {txHash && <div className="mt-2 text-xs text-gray-400 break-all">Tx: {txHash}</div>}
        </div>
      )}

      {/* Execute Button */}
      <button
        onClick={handleExecuteTrade}
        disabled={
          !quote || status === "pending" || status === "preparing" || (isBuy ? needsUsdcApproval : needsOptionApproval)
        }
        className={`w-full py-3 px-4 rounded-lg font-medium transition-colors ${
          !quote || status === "pending" || status === "preparing" || (isBuy ? needsUsdcApproval : needsOptionApproval)
            ? "bg-gray-800 text-gray-500 cursor-not-allowed"
            : isBuy
              ? "bg-green-500 hover:bg-green-600 text-white"
              : "bg-red-500 hover:bg-red-600 text-white"
        }`}
      >
        {status === "pending" || status === "preparing"
          ? "Processing..."
          : (isBuy ? needsUsdcApproval : needsOptionApproval)
            ? "Approval Required"
            : isBuy
              ? "Buy Option"
              : "Sell Option"}
      </button>
    </div>
  );
}
