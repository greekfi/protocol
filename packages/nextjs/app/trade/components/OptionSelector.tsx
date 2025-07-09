"use client";

import React, { useState } from "react";
import TooltipButton from "../../shared/components/TooltipButton";
import { ExpirationGroup, OptionData, useGetOptionsByPair } from "../../shared/hooks/useGetOptionsByPair";
import { OptionPair } from "../../shared/hooks/useGetPairs";
import { Address } from "viem";
import { formatEther } from "viem";

interface OptionSelectorProps {
  setOptionAddress: (address: Address) => void;
  selectedOption?: OptionData;
  selectedPair: OptionPair | null;
}

export default function OptionSelector({ setOptionAddress, selectedOption, selectedPair }: OptionSelectorProps) {
  const [selectedExpiration, setSelectedExpiration] = useState<ExpirationGroup | null>(null);

  // Reset selections when pair changes
  React.useEffect(() => {
    setSelectedExpiration(null);
    setOptionAddress("0x0" as Address);
  }, [selectedPair, setOptionAddress]);

  const { expirationGroups } = useGetOptionsByPair(selectedPair?.collateral, selectedPair?.consideration);

  // Placeholder bid/ask data for now
  const getPlaceholderBidAsk = () => ({
    bid: BigInt("1000000000000000000"), // 1 ETH in wei
    ask: BigInt("1100000000000000000"), // 1.1 ETH in wei
    bidSize: BigInt("1000000000000000000"), // 1 ETH
    askSize: BigInt("500000000000000000"), // 0.5 ETH
    lastPrice: BigInt("1050000000000000000"), // 1.05 ETH
    volume24h: BigInt("10000000000000000000"), // 10 ETH
  });

  const handleExpirationSelect = (expiration: ExpirationGroup) => {
    setSelectedExpiration(expiration);
  };

  const handleOptionSelect = (option: OptionData) => {
    setOptionAddress(option.address);
  };

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <h2 className="text-lg font-semibold text-white">Select Option</h2>
        <TooltipButton
          tooltipText="Choose an expiration and strike to trade options"
          className="text-blue-400 hover:text-blue-300"
        />
      </div>

      {/* Expiration Selection */}
      {selectedPair && (
        <div className="space-y-3">
          <h3 className="text-md font-medium text-gray-300">2. Select Expiration</h3>
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-3">
            {expirationGroups.map(expiration => (
              <button
                key={expiration.expirationDate.toString()}
                onClick={() => handleExpirationSelect(expiration)}
                className={`p-3 border rounded-lg text-left transition-colors ${
                  selectedExpiration?.expirationDate === expiration.expirationDate
                    ? "border-blue-500 bg-blue-900/20"
                    : "border-gray-600 hover:border-blue-500 hover:bg-gray-700"
                }`}
              >
                <div className="text-sm text-gray-400">Expiration</div>
                <div className="text-white font-medium">{expiration.formattedDate}</div>
                <div className="text-xs text-gray-500">{expiration.options.length} strike(s) available</div>
              </button>
            ))}
          </div>
        </div>
      )}

      {/* Strike Selection */}
      {selectedExpiration && (
        <div className="space-y-3">
          <h3 className="text-md font-medium text-gray-300">3. Select Strike</h3>
          <div className="overflow-x-auto">
            <table className="w-full border-collapse">
              <thead>
                <tr className="border-b border-gray-600">
                  <th className="text-left p-2 text-sm text-gray-400">Type</th>
                  <th className="text-left p-2 text-sm text-gray-400">Strike</th>
                  <th className="text-left p-2 text-sm text-gray-400">Bid</th>
                  <th className="text-left p-2 text-sm text-gray-400">Ask</th>
                  <th className="text-left p-2 text-sm text-gray-400">Bid Size</th>
                  <th className="text-left p-2 text-sm text-gray-400">Ask Size</th>
                  <th className="text-left p-2 text-sm text-gray-400">Action</th>
                </tr>
              </thead>
              <tbody>
                {selectedExpiration.options.map(option => {
                  const bidAsk = getPlaceholderBidAsk();
                  const isSelected = selectedOption?.address === option.address;

                  return (
                    <tr
                      key={option.address}
                      className={`border-b border-gray-700 hover:bg-gray-700/50 ${isSelected ? "bg-blue-900/20" : ""}`}
                    >
                      <td className="p-2">
                        <span
                          className={`px-2 py-1 rounded text-xs font-medium ${
                            option.isPut ? "bg-red-900/50 text-red-300" : "bg-green-900/50 text-green-300"
                          }`}
                        >
                          {option.isPut ? "PUT" : "CALL"}
                        </span>
                      </td>
                      <td className="p-2 text-white">
                        {formatEther(option.strike)} {selectedPair?.consideration.slice(0, 6)}...
                        {selectedPair?.consideration.slice(-4)}
                      </td>
                      <td className="p-2 text-green-400">
                        {formatEther(bidAsk.bid)} {selectedPair?.collateral.slice(0, 6)}...
                        {selectedPair?.collateral.slice(-4)}
                      </td>
                      <td className="p-2 text-red-400">
                        {formatEther(bidAsk.ask)} {selectedPair?.collateral.slice(0, 6)}...
                        {selectedPair?.collateral.slice(-4)}
                      </td>
                      <td className="p-2 text-gray-300">{formatEther(bidAsk.bidSize)}</td>
                      <td className="p-2 text-gray-300">{formatEther(bidAsk.askSize)}</td>
                      <td className="p-2">
                        <button
                          onClick={() => handleOptionSelect(option)}
                          className={`px-3 py-1 rounded text-sm font-medium transition-colors ${
                            isSelected ? "bg-blue-600 text-white" : "bg-gray-600 text-gray-300 hover:bg-gray-500"
                          }`}
                        >
                          {isSelected ? "Selected" : "Select"}
                        </button>
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        </div>
      )}

      {!selectedPair && (
        <div className="text-center py-8 text-gray-400">
          <p>Select a token pair to view available options</p>
        </div>
      )}
    </div>
  );
}
