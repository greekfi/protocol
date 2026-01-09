"use client";

import { useState } from "react";
import { TokenSelector } from "./components/TokenSelector";
import { OptionsGrid } from "./components/OptionsGrid";
import { TradePanel } from "./components/TradePanel";
import Navbar from "../mint/components/Navbar";

export default function TradePage() {
  const [selectedToken, setSelectedToken] = useState<string | null>(null);
  const [selectedOption, setSelectedOption] = useState<{
    optionAddress: string;
    strike: bigint;
    expiration: bigint;
    isPut: boolean;
    collateralAddress: string;
    considerationAddress: string;
  } | null>(null);

  return (
    <div className="min-h-screen bg-black text-gray-200">
      <div className="max-w-7xl mx-auto p-6">
        <Navbar />
        <h1 className="text-3xl font-light text-blue-300 mb-8 mt-6">Trade Options</h1>

        {/* Token Selector */}
        <div className="mb-6">
          <TokenSelector selectedToken={selectedToken} onSelectToken={setSelectedToken} />
        </div>

        {/* Options Grid */}
        {selectedToken && (
          <div className="mb-6">
            <OptionsGrid selectedToken={selectedToken} onSelectOption={setSelectedOption} />
          </div>
        )}

        {/* Trade Panel */}
        {selectedOption && (
          <div className="mt-6">
            <TradePanel selectedOption={selectedOption} onClose={() => setSelectedOption(null)} />
          </div>
        )}
      </div>
    </div>
  );
}
