"use client";

import { useState } from "react";
import Navbar from "../mint/components/Navbar";
import { type OptionSelection, OptionsGrid } from "./components/OptionsGrid";
import { TokenSelector } from "./components/TokenSelector";
import { TradePanel } from "./components/TradePanel";

export default function TradePage() {
  const [selectedToken, setSelectedToken] = useState<string | null>(null);
  const [selectedOption, setSelectedOption] = useState<{
    optionAddress: string;
    strike: bigint;
    expiration: bigint;
    isPut: boolean;
    collateralAddress: string;
    considerationAddress: string;
    isBuy: boolean;
  } | null>(null);

  const handleSelectOption = (selection: OptionSelection) => {
    setSelectedOption({
      optionAddress: selection.option.optionAddress,
      strike: selection.option.strike,
      expiration: selection.option.expiration,
      isPut: selection.option.isPut,
      collateralAddress: selection.option.collateralAddress,
      considerationAddress: selection.option.considerationAddress,
      isBuy: selection.isBuy,
    });
  };

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
            <OptionsGrid selectedToken={selectedToken} onSelectOption={handleSelectOption} />
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
