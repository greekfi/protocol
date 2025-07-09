"use client";

import { useEffect, useState } from "react";
import { OptionPair, useGetPairs } from "../../shared/hooks/useGetPairs";
import { erc20Abi } from "viem";
import { useReadContracts } from "wagmi";

interface PairSelectorProps {
  selectedPair: OptionPair | null;
  onPairSelect: (pair: OptionPair) => void;
}

interface PairWithNames extends OptionPair {
  collateralName: string;
  considerationName: string;
}

export default function PairSelector({ selectedPair, onPairSelect }: PairSelectorProps) {
  const { pairs, isLoading, error } = useGetPairs();
  const [pairsWithNames, setPairsWithNames] = useState<PairWithNames[]>([]);

  // Create contracts array for all token names
  const allTokenContracts = pairs.flatMap(pair => [
    {
      address: pair.collateral,
      abi: erc20Abi,
      functionName: "name" as const,
    },
    {
      address: pair.consideration,
      abi: erc20Abi,
      functionName: "name" as const,
    },
  ]);

  const { data: tokenNames } = useReadContracts({
    contracts: allTokenContracts,
    query: {
      enabled: pairs.length > 0,
    },
  });

  // Combine pairs with names
  useEffect(() => {
    if (pairs.length > 0 && tokenNames) {
      const pairsWithNamesData = pairs.map((pair, index) => {
        const collateralNameIndex = index * 2;
        const considerationNameIndex = index * 2 + 1;

        return {
          ...pair,
          collateralName: (tokenNames[collateralNameIndex]?.result as string) || `Token ${index + 1}`,
          considerationName: (tokenNames[considerationNameIndex]?.result as string) || `Token ${index + 1}`,
        };
      });
      setPairsWithNames(pairsWithNamesData);
    }
  }, [pairs, tokenNames]);

  if (isLoading) {
    return (
      <div className="p-4 bg-gray-800 rounded-lg">
        <div className="animate-pulse">
          <div className="h-4 bg-gray-700 rounded w-1/4 mb-2"></div>
          <div className="h-10 bg-gray-700 rounded"></div>
        </div>
      </div>
    );
  }

  if (error) {
    return (
      <div className="p-4 bg-red-900/20 border border-red-500 rounded-lg">
        <p className="text-red-400">Error loading pairs: {error.message}</p>
      </div>
    );
  }

  if (pairs.length === 0) {
    return (
      <div className="p-4 bg-gray-800 rounded-lg">
        <p className="text-gray-400">No pairs available</p>
      </div>
    );
  }

  return (
    <div className="space-y-4">
      <div>
        <label className="block text-sm font-medium text-gray-300 mb-2">Select Trading Pair</label>
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-3">
          {pairsWithNames.map(pair => (
            <button
              key={`${pair.collateral}-${pair.consideration}`}
              onClick={() => onPairSelect(pair)}
              className={`p-4 rounded-lg border transition-all duration-200 ${
                selectedPair &&
                selectedPair.collateral === pair.collateral &&
                selectedPair.consideration === pair.consideration
                  ? "border-blue-500 bg-blue-500/10"
                  : "border-gray-600 bg-gray-700 hover:border-gray-500 hover:bg-gray-600"
              }`}
            >
              <div className="text-center">
                <div className="text-sm font-medium text-gray-300">
                  {pair.collateralName} / {pair.considerationName}
                </div>
                <div className="text-xs text-gray-500 mt-1">
                  {pair.collateral.slice(0, 6)}...{pair.collateral.slice(-4)} / {pair.consideration.slice(0, 6)}...
                  {pair.consideration.slice(-4)}
                </div>
              </div>
            </button>
          ))}
        </div>
      </div>

      {selectedPair && (
        <div className="p-4 bg-blue-500/10 border border-blue-500 rounded-lg">
          <h3 className="text-sm font-medium text-blue-400 mb-2">Selected Pair:</h3>
          <div className="text-sm text-gray-300">
            <div>Collateral: {selectedPair.collateral}</div>
            <div>Consideration: {selectedPair.consideration}</div>
          </div>
        </div>
      )}
    </div>
  );
}
