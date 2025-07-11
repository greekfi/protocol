"use client";

import React from "react";
import { Address } from "../../../components/scaffold-eth/Address/Address";
import { useGetOptionsByPair } from "../../shared/hooks/useGetOptionsByPair";
import { OptionPair } from "../../shared/hooks/useGetPairs";

interface OptionViewerProps {
  selectedPair: OptionPair | null;
}

export default function OptionViewer({ selectedPair }: OptionViewerProps) {
  const { expirationGroups } = useGetOptionsByPair(
    selectedPair?.collateral || "0x0000000000000000000000000000000000000000",
    selectedPair?.consideration || "0x0000000000000000000000000000000000000000",
  );

  // Get all unique strike prices across all expiration groups
  const allStrikes = new Set<number>();
  expirationGroups.forEach(group => {
    group.options.forEach(option => {
      allStrikes.add(option.strikePrice);
    });
  });

  // Convert to array and sort
  const sortedStrikes = Array.from(allStrikes).sort((a, b) => Number(a - b));

  // Create a map for quick lookup of options by expiration and strike
  const optionMap = new Map<string, string>();
  expirationGroups.forEach(group => {
    group.options.forEach(option => {
      const key = `${group.expirationDate}-${option.strike}`;
      optionMap.set(key, option.longOption);
    });
  });

  if (!selectedPair) {
    return (
      <div className="p-4">
        <h1 className="text-2xl font-bold mb-4">Option Viewer</h1>
        <p className="text-gray-500">Please select a token pair to view options.</p>
      </div>
    );
  }

  if (expirationGroups.length === 0) {
    return (
      <div className="p-4">
        <h1 className="text-2xl font-bold mb-4">Option Viewer</h1>
        <p className="text-gray-500">No options found for the selected pair.</p>
        <div className="mt-2 text-sm text-gray-400">
          <p>
            Collateral: <Address address={selectedPair.collateral} />
          </p>
          <p>
            Consideration: <Address address={selectedPair.consideration} />
          </p>
        </div>
      </div>
    );
  }

  return (
    <div className="p-4">
      <div className="mb-4">
        <h1 className="text-2xl font-bold mb-2">Option Viewer</h1>
        <div className="text-sm text-gray-600">
          <p>
            <strong>Collateral:</strong> {selectedPair.collateralName} ({selectedPair.collateralSymbol}) -{" "}
            <Address address={selectedPair.collateral} />
          </p>
          <p>
            <strong>Consideration:</strong> {selectedPair.considerationName} ({selectedPair.considerationSymbol}) -{" "}
            <Address address={selectedPair.consideration} />
          </p>
        </div>
      </div>

      <div className="overflow-x-auto">
        <table className="min-w-full border border-gray-300">
          <thead>
            <tr className="bg-gray-100">
              <th className="border border-gray-300 px-4 py-2 text-left">Strike Price</th>
              {expirationGroups.map(group => (
                <th key={group.expirationDate.toString()} className="border border-gray-300 px-4 py-2 text-center">
                  {group.formattedDate}
                </th>
              ))}
            </tr>
          </thead>
          <tbody>
            {sortedStrikes.map(strike => (
              <tr key={strike.toString()}>
                <td className="border border-gray-300 px-4 py-2 font-medium">{strike.toString()}</td>
                {expirationGroups.map(group => {
                  const key = `${group.expirationDate}-${strike}`;
                  const optionData = optionMap.get(key);

                  return (
                    <td key={key} className="border border-gray-300 px-4 py-2 text-center">
                      {optionData ? <Address address={optionData} /> : <span className="text-gray-400">-</span>}
                    </td>
                  );
                })}
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}
