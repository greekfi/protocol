import { useEffect, useState } from "react";
import { useTokenMap } from "../../mint/hooks/useTokenMap";
import { useRfqPricingStream } from "../hooks/useRfqPricingStream";
import { useRfqQuote } from "../hooks/useRfqQuote";
import { formatUnits, parseUnits } from "viem";
import { useAccount, useChainId, useReadContract, useWaitForTransactionReceipt, useWriteContract } from "wagmi";
import deployedContracts from "~~/contracts/deployedContracts";

// Option ABI for mint and exercise
const OPTION_ABI = [
  {
    name: "mint",
    type: "function",
    stateMutability: "nonpayable",
    inputs: [{ name: "amount", type: "uint256" }],
    outputs: [],
  },
  {
    name: "exercise",
    type: "function",
    stateMutability: "nonpayable",
    inputs: [{ name: "amount", type: "uint256" }],
    outputs: [],
  },
  {
    name: "redeem",
    type: "function",
    stateMutability: "nonpayable",
    inputs: [{ name: "amount", type: "uint256" }],
    outputs: [],
  },
  {
    name: "redemption",
    type: "function",
    stateMutability: "view",
    inputs: [],
    outputs: [{ type: "address" }],
  },
  {
    name: "balanceOf",
    type: "function",
    stateMutability: "view",
    inputs: [{ name: "account", type: "address" }],
    outputs: [{ type: "uint256" }],
  },
] as const;

// ERC20 ABI
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
  {
    name: "symbol",
    type: "function",
    stateMutability: "view",
    inputs: [],
    outputs: [{ type: "string" }],
  },
] as const;

interface OptionsTradePanelProps {
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

type TradeAction = "mint" | "exercise" | "redeem";

export function OptionsTradePanel({ selectedOption, onClose }: OptionsTradePanelProps) {
  const [action, setAction] = useState<TradeAction>("mint");
  const [amount, setAmount] = useState<string>("1");
  const { allTokensMap } = useTokenMap();
  const { address: userAddress } = useAccount();
  const chainId = useChainId();

  // Get deployed factory address for approvals
  const contracts = deployedContracts[chainId as keyof typeof deployedContracts];
  const factoryAddress = contracts?.OptionFactory?.address;

  // Get redemption contract address
  const { data: redemptionAddress } = useReadContract({
    address: selectedOption.optionAddress as `0x${string}`,
    abi: OPTION_ABI,
    functionName: "redemption",
  });

  // Get RFQ pricing stream for live prices
  const { getPrice, isConnected: isPricingConnected } = useRfqPricingStream({
    enabled: true,
    options: [selectedOption.optionAddress],
  });

  const rfqPrice = getPrice(selectedOption.optionAddress);

  // Get token symbols
  const collateralSymbol =
    Object.values(allTokensMap).find(t => t.address.toLowerCase() === selectedOption.collateralAddress.toLowerCase())
      ?.symbol || "COLL";
  const considerationSymbol =
    Object.values(allTokensMap).find(t => t.address.toLowerCase() === selectedOption.considerationAddress.toLowerCase())
      ?.symbol || "CONS";

  // Get token decimals
  const { data: collateralDecimals } = useReadContract({
    address: selectedOption.collateralAddress as `0x${string}`,
    abi: ERC20_ABI,
    functionName: "decimals",
  });

  const { data: considerationDecimals } = useReadContract({
    address: selectedOption.considerationAddress as `0x${string}`,
    abi: ERC20_ABI,
    functionName: "decimals",
  });

  // User's option token balance
  const { data: optionBalance, refetch: refetchOptionBalance } = useReadContract({
    address: selectedOption.optionAddress as `0x${string}`,
    abi: OPTION_ABI,
    functionName: "balanceOf",
    args: userAddress ? [userAddress] : undefined,
    query: { enabled: !!userAddress },
  });

  // Collateral allowance (for minting)
  const { data: collateralAllowance, refetch: refetchCollateralAllowance } = useReadContract({
    address: selectedOption.collateralAddress as `0x${string}`,
    abi: ERC20_ABI,
    functionName: "allowance",
    args: userAddress && factoryAddress ? [userAddress, factoryAddress as `0x${string}`] : undefined,
    query: { enabled: !!userAddress && !!factoryAddress },
  });

  // Consideration allowance (for exercising)
  const { data: considerationAllowance, refetch: refetchConsiderationAllowance } = useReadContract({
    address: selectedOption.considerationAddress as `0x${string}`,
    abi: ERC20_ABI,
    functionName: "allowance",
    args: userAddress && factoryAddress ? [userAddress, factoryAddress as `0x${string}`] : undefined,
    query: { enabled: !!userAddress && !!factoryAddress },
  });

  // Approval transactions
  const {
    writeContract: approveCollateral,
    data: collateralApprovalHash,
    isPending: isApprovingCollateral,
  } = useWriteContract();
  const { isSuccess: isCollateralApprovalSuccess } = useWaitForTransactionReceipt({
    hash: collateralApprovalHash,
  });

  const {
    writeContract: approveConsideration,
    data: considerationApprovalHash,
    isPending: isApprovingConsideration,
  } = useWriteContract();
  const { isSuccess: isConsiderationApprovalSuccess } = useWaitForTransactionReceipt({
    hash: considerationApprovalHash,
  });

  // Refetch allowances after approval
  useEffect(() => {
    if (isCollateralApprovalSuccess) {
      refetchCollateralAllowance();
    }
  }, [isCollateralApprovalSuccess, refetchCollateralAllowance]);

  useEffect(() => {
    if (isConsiderationApprovalSuccess) {
      refetchConsiderationAllowance();
    }
  }, [isConsiderationApprovalSuccess, refetchConsiderationAllowance]);

  // Trade execution
  const { writeContract: executeAction, data: actionHash, isPending: isExecuting } = useWriteContract();
  const { isSuccess: isActionSuccess, isLoading: isActionPending } = useWaitForTransactionReceipt({
    hash: actionHash,
  });

  // Refetch balance after successful action
  useEffect(() => {
    if (isActionSuccess) {
      refetchOptionBalance();
    }
  }, [isActionSuccess, refetchOptionBalance]);

  // Calculate amounts based on action
  const amountBigInt = amount ? parseUnits(amount, 18) : 0n;

  // For minting: need collateral
  // For exercising: need consideration (strike price * amount)
  const collateralNeeded = action === "mint" ? amountBigInt : 0n;
  const considerationNeeded = action === "exercise" ? (amountBigInt * selectedOption.strike) / BigInt(10 ** 18) : 0n;

  const needsCollateralApproval = Boolean(
    action === "mint" &&
    factoryAddress &&
    collateralAllowance !== undefined &&
    collateralNeeded > 0n &&
    collateralAllowance < collateralNeeded,
  );

  const needsConsiderationApproval = Boolean(
    action === "exercise" &&
    factoryAddress &&
    considerationAllowance !== undefined &&
    considerationNeeded > 0n &&
    considerationAllowance < considerationNeeded,
  );

  const handleApproveCollateral = () => {
    if (!factoryAddress) return;
    approveCollateral({
      address: selectedOption.collateralAddress as `0x${string}`,
      abi: ERC20_ABI,
      functionName: "approve",
      args: [
        factoryAddress as `0x${string}`,
        BigInt("0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"),
      ],
    });
  };

  const handleApproveConsideration = () => {
    if (!factoryAddress) return;
    approveConsideration({
      address: selectedOption.considerationAddress as `0x${string}`,
      abi: ERC20_ABI,
      functionName: "approve",
      args: [
        factoryAddress as `0x${string}`,
        BigInt("0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"),
      ],
    });
  };

  const handleExecuteAction = () => {
    if (!amountBigInt) return;

    executeAction({
      address: selectedOption.optionAddress as `0x${string}`,
      abi: OPTION_ABI,
      functionName: action,
      args: [amountBigInt],
    });
  };

  // Format dates
  const expirationDate = new Date(Number(selectedOption.expiration) * 1000);
  const strikeFormatted = formatUnits(selectedOption.strike, 18);

  const isExpired = Date.now() > Number(selectedOption.expiration) * 1000;

  return (
    <div className="p-6 bg-black/80 border border-gray-800 rounded-lg shadow-lg">
      <div className="flex justify-between items-center mb-4">
        <h2 className="text-xl font-light text-blue-300">Trade Option (On-Chain)</h2>
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
          <div>
            <div className="text-gray-400">Expiration</div>
            <div className={`font-medium ${isExpired ? "text-red-400" : "text-blue-300"}`}>
              {expirationDate.toLocaleDateString()} {expirationDate.toLocaleTimeString()}
              {isExpired && " (EXPIRED)"}
            </div>
          </div>
          <div>
            <div className="text-gray-400">Your Balance</div>
            <div className="text-blue-300 font-medium">
              {optionBalance !== undefined ? formatUnits(optionBalance, 18) : "Loading..."}
            </div>
          </div>
        </div>

        {/* RFQ Pricing */}
        {rfqPrice && (
          <div className="mt-4 pt-4 border-t border-gray-700">
            <div className="text-sm text-gray-400 mb-2">RFQ Pricing {isPricingConnected ? "🟢" : "⚪"}</div>
            <div className="grid grid-cols-4 gap-2 text-sm">
              <div>
                <div className="text-gray-500">Bid</div>
                <div className="text-green-400">${rfqPrice.bid.toFixed(4)}</div>
              </div>
              <div>
                <div className="text-gray-500">Ask</div>
                <div className="text-red-400">${rfqPrice.ask.toFixed(4)}</div>
              </div>
              <div>
                <div className="text-gray-500">Spot</div>
                <div className="text-blue-300">${rfqPrice.spotPrice.toFixed(2)}</div>
              </div>
              <div>
                <div className="text-gray-500">Delta</div>
                <div className="text-blue-300">{rfqPrice.delta.toFixed(3)}</div>
              </div>
            </div>
          </div>
        )}
      </div>

      {/* Action Selector */}
      <div className="mb-4">
        <div className="text-gray-400 mb-2 text-sm">Action</div>
        <div className="flex gap-2">
          <button
            onClick={() => setAction("mint")}
            disabled={isExpired}
            className={`flex-1 py-2 px-4 rounded-lg transition-colors ${
              action === "mint"
                ? "bg-green-500 text-white"
                : "bg-gray-900 text-gray-400 border border-gray-700 hover:border-green-500"
            } ${isExpired ? "opacity-50 cursor-not-allowed" : ""}`}
          >
            Mint
          </button>
          <button
            onClick={() => setAction("exercise")}
            disabled={isExpired}
            className={`flex-1 py-2 px-4 rounded-lg transition-colors ${
              action === "exercise"
                ? "bg-blue-500 text-white"
                : "bg-gray-900 text-gray-400 border border-gray-700 hover:border-blue-500"
            } ${isExpired ? "opacity-50 cursor-not-allowed" : ""}`}
          >
            Exercise
          </button>
          <button
            onClick={() => setAction("redeem")}
            className={`flex-1 py-2 px-4 rounded-lg transition-colors ${
              action === "redeem"
                ? "bg-purple-500 text-white"
                : "bg-gray-900 text-gray-400 border border-gray-700 hover:border-purple-500"
            }`}
          >
            Redeem
          </button>
        </div>
      </div>

      {/* Action Description */}
      <div className="mb-4 p-3 bg-gray-900/50 rounded-lg border border-gray-700 text-sm text-gray-400">
        {action === "mint" && (
          <>
            <strong>Mint:</strong> Deposit {collateralSymbol} collateral to create Option + Redemption tokens.
          </>
        )}
        {action === "exercise" && (
          <>
            <strong>Exercise:</strong> Pay {considerationSymbol} at strike price to receive {collateralSymbol}{" "}
            collateral.
          </>
        )}
        {action === "redeem" && (
          <>
            <strong>Redeem:</strong> Burn matched Option + Redemption pairs to get back {collateralSymbol} collateral.
          </>
        )}
      </div>

      {/* Amount Input */}
      <div className="mb-4">
        <label className="block text-gray-400 mb-2 text-sm">Amount</label>
        <input
          type="number"
          value={amount}
          onChange={e => setAmount(e.target.value)}
          placeholder="0.0"
          step="any"
          min="0"
          className="w-full p-3 rounded-lg border border-gray-700 bg-black/60 text-blue-300 focus:outline-none focus:border-blue-500"
        />
        {action === "mint" && collateralDecimals !== undefined && (
          <div className="mt-1 text-xs text-gray-500">
            Collateral needed: {formatUnits(collateralNeeded, collateralDecimals)} {collateralSymbol}
          </div>
        )}
        {action === "exercise" && considerationDecimals !== undefined && (
          <div className="mt-1 text-xs text-gray-500">
            Payment needed: {formatUnits(considerationNeeded, considerationDecimals)} {considerationSymbol}
          </div>
        )}
      </div>

      {/* Approval Sections */}
      {action === "mint" && (
        <div className="mb-4 p-4 bg-gray-900 rounded-lg border border-gray-700">
          <h3 className="text-sm font-medium text-gray-300 mb-3">{collateralSymbol} Approval</h3>
          <div className="space-y-3">
            <div className="flex justify-between items-center text-sm">
              <span className="text-gray-400">Current Allowance:</span>
              <span className="text-blue-300 font-mono">
                {collateralAllowance !== undefined && collateralDecimals !== undefined
                  ? formatUnits(collateralAllowance, collateralDecimals)
                  : "Loading..."}
              </span>
            </div>
            <button
              onClick={handleApproveCollateral}
              disabled={isApprovingCollateral || !needsCollateralApproval}
              className={`w-full py-2.5 px-4 rounded-lg font-medium transition-colors ${
                isApprovingCollateral || !needsCollateralApproval
                  ? "bg-gray-800 text-gray-500 cursor-not-allowed"
                  : "bg-blue-500 hover:bg-blue-600 text-white"
              }`}
            >
              {isApprovingCollateral
                ? "Approving..."
                : needsCollateralApproval
                  ? `Approve ${collateralSymbol}`
                  : "Approved ✓"}
            </button>
          </div>
        </div>
      )}

      {action === "exercise" && (
        <div className="mb-4 p-4 bg-gray-900 rounded-lg border border-gray-700">
          <h3 className="text-sm font-medium text-gray-300 mb-3">{considerationSymbol} Approval</h3>
          <div className="space-y-3">
            <div className="flex justify-between items-center text-sm">
              <span className="text-gray-400">Current Allowance:</span>
              <span className="text-blue-300 font-mono">
                {considerationAllowance !== undefined && considerationDecimals !== undefined
                  ? formatUnits(considerationAllowance, considerationDecimals)
                  : "Loading..."}
              </span>
            </div>
            <button
              onClick={handleApproveConsideration}
              disabled={isApprovingConsideration || !needsConsiderationApproval}
              className={`w-full py-2.5 px-4 rounded-lg font-medium transition-colors ${
                isApprovingConsideration || !needsConsiderationApproval
                  ? "bg-gray-800 text-gray-500 cursor-not-allowed"
                  : "bg-blue-500 hover:bg-blue-600 text-white"
              }`}
            >
              {isApprovingConsideration
                ? "Approving..."
                : needsConsiderationApproval
                  ? `Approve ${considerationSymbol}`
                  : "Approved ✓"}
            </button>
          </div>
        </div>
      )}

      {/* Transaction Status */}
      {(isExecuting || isActionPending || isActionSuccess) && (
        <div
          className={`mb-4 p-4 rounded-lg border ${
            isActionSuccess ? "bg-green-900/20 border-green-700" : "bg-blue-900/20 border-blue-700"
          }`}
        >
          <div className={isActionSuccess ? "text-green-300" : "text-blue-300"}>
            {isExecuting && "Preparing transaction..."}
            {isActionPending && "Transaction pending..."}
            {isActionSuccess && `${action.charAt(0).toUpperCase() + action.slice(1)} successful!`}
          </div>
          {actionHash && <div className="mt-2 text-xs text-gray-400 break-all">Tx: {actionHash}</div>}
        </div>
      )}

      {/* Execute Button */}
      <button
        onClick={handleExecuteAction}
        disabled={
          !amount ||
          parseFloat(amount) <= 0 ||
          isExecuting ||
          isActionPending ||
          (action === "mint" && needsCollateralApproval) ||
          (action === "exercise" && needsConsiderationApproval) ||
          (action !== "redeem" && isExpired)
        }
        className={`w-full py-3 px-4 rounded-lg font-medium transition-colors ${
          !amount ||
          parseFloat(amount) <= 0 ||
          isExecuting ||
          isActionPending ||
          (action === "mint" && needsCollateralApproval) ||
          (action === "exercise" && needsConsiderationApproval) ||
          (action !== "redeem" && isExpired)
            ? "bg-gray-800 text-gray-500 cursor-not-allowed"
            : action === "mint"
              ? "bg-green-500 hover:bg-green-600 text-white"
              : action === "exercise"
                ? "bg-blue-500 hover:bg-blue-600 text-white"
                : "bg-purple-500 hover:bg-purple-600 text-white"
        }`}
      >
        {isExecuting || isActionPending
          ? "Processing..."
          : (action === "mint" && needsCollateralApproval) || (action === "exercise" && needsConsiderationApproval)
            ? "Approval Required"
            : action === "mint"
              ? "Mint Options"
              : action === "exercise"
                ? "Exercise Options"
                : "Redeem Options"}
      </button>
    </div>
  );
}
