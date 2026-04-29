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
        {/* Underlying picker — the page title lives in the navbar (SiteHeader). */}
        <div className="flex flex-wrap items-center gap-x-6 gap-y-3 mb-8 mt-6">
          <div className="flex-1 min-w-[18rem]">
            <TokenGrid tokens={CALL_UNDERLYINGS} selected={selectedSymbol} onSelect={setSelectedSymbol} />
          </div>
        </div>

        {/* Options chain section: trade panel slot on top, grid below. */}
        {selectedTokenAddress && (
          <div className="p-6 bg-black/80 border border-gray-800 rounded-lg shadow-lg space-y-6">
            <div className="min-h-[6rem]">
              {selectedOption ? (
                <TradePanel selectedOption={selectedOption} onClose={() => setSelectedOption(null)} />
              ) : (
                <div className="text-sm text-gray-500 italic">
                  Pick a strike and expiry below to load the trade panel.
                </div>
              )}
            </div>

            <div className="border-t border-gray-800 -mx-6" />

            <OptionsGrid
              selectedToken={selectedTokenAddress}
              onSelectOption={handleSelectOption}
              selected={
                selectedOption
                  ? { optionAddress: selectedOption.optionAddress, isBuy: selectedOption.isBuy }
                  : null
              }
            />
          </div>
        )}
      </div>
      <SiteFooter />
    </div>
  );
}
