"use client";

import { useState } from "react";
import { TokenGrid } from "../components/options/TokenGrid";
import { SiteFooter } from "../components/SiteFooter";
import { SiteHeader } from "../components/SiteHeader";
import { useTokenMap } from "../mint/hooks/useTokenMap";
import { CALL_UNDERLYINGS } from "../yield/data";
import { type OptionSelection, OptionsGrid } from "./components/OptionsGrid";
import { TradePanel } from "./components/TradePanel";

export default function TradePage() {
  // TokenGrid emits a symbol; OptionsGrid expects an address. Resolve via the token map.
  const { allTokensMap } = useTokenMap();
  const [selectedSymbol, setSelectedSymbol] = useState<string | null>(null);
  const selectedTokenAddress = selectedSymbol ? allTokensMap[selectedSymbol]?.address ?? null : null;

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
      <SiteHeader />
      <div className="max-w-7xl mx-auto p-6">
        <h1 className="text-3xl font-light text-blue-300 mb-8 mt-6">Trade Options</h1>

        {/* Underlying picker — same TokenGrid as /yield */}
        <div className="mb-6">
          <TokenGrid tokens={CALL_UNDERLYINGS} selected={selectedSymbol} onSelect={setSelectedSymbol} />
        </div>

        {/* Options Grid (existing /trade matrix) */}
        {selectedTokenAddress && (
          <div className="mb-6">
            <OptionsGrid selectedToken={selectedTokenAddress} onSelectOption={handleSelectOption} />
          </div>
        )}

        {/* Trade Panel */}
        {selectedOption && (
          <div className="mt-6">
            <TradePanel selectedOption={selectedOption} onClose={() => setSelectedOption(null)} />
          </div>
        )}
      </div>
      <SiteFooter />
    </div>
  );
}
