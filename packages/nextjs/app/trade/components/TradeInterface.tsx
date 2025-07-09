"use client";

import { useState } from "react";
import TokenBalance from "../../mint/components/TokenBalance";
import TooltipButton from "../../mint/components/TooltipButton";
import { formatEther, parseEther } from "viem";
import { useScaffoldWriteContract } from "~~/hooks/scaffold-eth";

interface TradeInterfaceProps {
  details: any; // Replace with proper type from your useGetDetails hook
}

export default function TradeInterface({ details }: TradeInterfaceProps) {
  const [amount, setAmount] = useState("");
  const [isLoading, setIsLoading] = useState(false);

  const { writeContractAsync: writeOptionContractAsync } = useScaffoldWriteContract({
    contractName: "LongOption",
  });

  const handleTrade = async (action: "buy" | "sell") => {
    if (!amount || !details?.optionAddress) return;

    setIsLoading(true);
    try {
      await writeOptionContractAsync({
        functionName: action === "buy" ? "mint" : "redeem",
        args: [parseEther(amount)],
      });
      setAmount("");
    } catch (error) {
      console.error(`Error ${action}ing options:`, error);
    } finally {
      setIsLoading(false);
    }
  };

  if (!details?.optionAddress) {
    return (
      <div className="text-center py-8 text-gray-400">
        <p>Select an option contract to start trading</p>
      </div>
    );
  }

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <h2 className="text-xl font-semibold text-white">Trade Options</h2>
        <TooltipButton
          tooltipText="Buy or sell options on this contract"
          className="text-blue-400 hover:text-blue-300"
        />
      </div>

      {/* Option Details */}
      <div className="grid grid-cols-1 md:grid-cols-3 gap-4 p-4 bg-gray-700 rounded-lg">
        <div>
          <div className="text-sm text-gray-400">Strike Price</div>
          <div className="text-white font-semibold">
            {details.strikePrice ? formatEther(details.strikePrice) : "N/A"} ETH
          </div>
        </div>
        <div>
          <div className="text-sm text-gray-400">Expiry</div>
          <div className="text-white font-semibold">
            {details.expiry ? new Date(Number(details.expiry) * 1000).toLocaleDateString() : "N/A"}
          </div>
        </div>
        <div>
          <div className="text-sm text-gray-400">Available Supply</div>
          <div className="text-white font-semibold">
            {details.totalSupply ? formatEther(details.totalSupply) : "N/A"}
          </div>
        </div>
      </div>

      {/* Trade Form */}
      <div className="space-y-4">
        <div>
          <label className="block text-sm font-medium text-gray-300 mb-2">Amount to Trade</label>
          <input
            type="number"
            value={amount}
            onChange={e => setAmount(e.target.value)}
            placeholder="0.0"
            className="w-full p-3 bg-gray-700 border border-gray-600 rounded-lg text-white placeholder-gray-400 focus:border-blue-500 focus:outline-none"
          />
        </div>

        <div className="flex gap-4">
          <button
            onClick={() => handleTrade("buy")}
            disabled={isLoading || !amount}
            className="flex-1 bg-green-600 hover:bg-green-700 disabled:bg-gray-600 text-white font-semibold py-3 px-4 rounded-lg transition-colors"
          >
            {isLoading ? "Processing..." : "Buy Options"}
          </button>
          <button
            onClick={() => handleTrade("sell")}
            disabled={isLoading || !amount}
            className="flex-1 bg-red-600 hover:bg-red-700 disabled:bg-gray-600 text-white font-semibold py-3 px-4 rounded-lg transition-colors"
          >
            {isLoading ? "Processing..." : "Sell Options"}
          </button>
        </div>
      </div>

      {/* User Balances */}
      <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
        <div className="p-4 bg-gray-700 rounded-lg">
          <TokenBalance label="Your Option Balance" tokenAddress={details.optionAddress} decimals={18} />
        </div>
        <div className="p-4 bg-gray-700 rounded-lg">
          <TokenBalance
            label="Your Collateral Balance"
            tokenAddress={details.collateralAddress}
            decimals={details.collateralDecimals}
          />
        </div>
      </div>
    </div>
  );
}
