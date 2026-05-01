"use client";

import { useState } from "react";
import { TokenGrid } from "../components/options/TokenGrid";
import { SiteFooter } from "../components/SiteFooter";
import { SiteHeader } from "../components/SiteHeader";
import { useTokenMap } from "../mint/hooks/useTokenMap";
import { CALL_UNDERLYINGS } from "../yield/data";
import type { HeldOption } from "./hooks/useAllHeldOptions";
import { HoldingsCard } from "./components/HoldingsCard";
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

  // Counter bumped to ask the TradePanel to open its exercise box (e.g. when
  // the user clicks "exercise" in the holdings list).
  const [openExerciseSignal, setOpenExerciseSignal] = useState(0);

  const handleSelectSymbol = (symbol: string) => {
    // Switching the underlying invalidates any in-flight buy/sell — drop it.
    if (symbol !== selectedSymbol) setSelectedOption(null);
    setSelectedSymbol(symbol);
  };

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

  // Click a holding → jump into the trade panel for that option. Switch the
  // underlying selector so the OptionsGrid shows the matching chain. Default
  // direction: sell to close a long; buy to close a naked short.
  const handleSelectHolding = (h: HeldOption) => {
    const underlyingAddr = h.isPut ? h.consideration : h.collateral;
    const symbol = Object.values(allTokensMap).find(
      t => t.address.toLowerCase() === underlyingAddr.toLowerCase(),
    )?.symbol;
    if (symbol) setSelectedSymbol(symbol);
    setSelectedOption({
      optionAddress: h.option,
      strike: h.strike,
      expiration: h.expiration,
      isPut: h.isPut,
      collateralAddress: h.collateral,
      considerationAddress: h.consideration,
      isBuy: h.optionBalance > 0n ? false : true,
    });
  };

  const handleExerciseHolding = (h: HeldOption) => {
    handleSelectHolding(h);
    setOpenExerciseSignal(s => s + 1);
  };

  return (
    <div className="min-h-screen bg-black text-gray-200">
      <SiteHeader />
      <div className="max-w-7xl mx-auto p-6 flex flex-col items-center text-center">
        {/* Single unified card. Once an option is picked, the TokenGrid pill
            moves *inside* the buy action card. */}
        <div className="w-full mt-6 p-6 bg-black/80 border border-gray-800 rounded-lg shadow-lg space-y-6 text-center">
          {!selectedTokenAddress && (
            <TokenGrid tokens={CALL_UNDERLYINGS} selected={selectedSymbol} onSelect={handleSelectSymbol} />
          )}

          {selectedTokenAddress && (
            <>
              {selectedOption ? (
                <TradePanel
                  selectedOption={selectedOption}
                  onClose={() => setSelectedOption(null)}
                  openExerciseSignal={openExerciseSignal}
                  tokenSelector={
                    <TokenGrid
                      tokens={CALL_UNDERLYINGS}
                      selected={selectedSymbol}
                      onSelect={handleSelectSymbol}
                    />
                  }
                  holdings={
                    <HoldingsCard
                      bare
                      onSelect={handleSelectHolding}
                      onExercise={handleExerciseHolding}
                    />
                  }
                />
              ) : (
                // Token picked, no strike yet: selected pill on the left with
                // the "pick a strike" hint boxed underneath at the same width;
                // holdings sit to the right.
                <div className="flex flex-wrap justify-center items-start gap-4 text-left">
                  <div className="flex flex-col items-start gap-2">
                    <TokenGrid
                      tokens={CALL_UNDERLYINGS}
                      selected={selectedSymbol}
                      onSelect={handleSelectSymbol}
                    />
                    <div className="w-full max-w-[7.5rem] text-xs text-gray-500 italic rounded-lg border border-gray-800 bg-black/40 px-2 py-2">
                      Pick a strike and expiry below.
                    </div>
                  </div>
                  <HoldingsCard onSelect={handleSelectHolding} onExercise={handleExerciseHolding} />
                </div>
              )}

              <OptionsGrid
                selectedToken={selectedTokenAddress}
                onSelectOption={handleSelectOption}
                selected={
                  selectedOption
                    ? { optionAddress: selectedOption.optionAddress, isBuy: selectedOption.isBuy }
                    : null
                }
              />
            </>
          )}
        </div>
      </div>
      <SiteFooter />
    </div>
  );
}
