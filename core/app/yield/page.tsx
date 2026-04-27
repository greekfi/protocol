"use client";

import { useState } from "react";
import { SiteFooter } from "../components/SiteFooter";
import { SiteHeader } from "../components/SiteHeader";
import { ModeToggle, type YieldMode } from "./components/ModeToggle";
import { StablecoinTabs } from "./components/StablecoinTabs";
import { TokenGrid } from "./components/TokenGrid";
import { YieldPanel } from "./components/YieldPanel";
import { CALL_UNDERLYINGS, PUT_UNDERLYINGS, STABLECOINS } from "./data";

export default function YieldPage() {
  const [mode, setMode] = useState<YieldMode>("calls");
  const [selectedStable, setSelectedStable] = useState<string>(STABLECOINS[0].symbol);
  const [selectedToken, setSelectedToken] = useState<string | null>(null);

  const tokens = mode === "calls" ? CALL_UNDERLYINGS : PUT_UNDERLYINGS;
  const selected = tokens.find(t => t.symbol === selectedToken) ?? null;

  const handleModeChange = (m: YieldMode) => {
    setMode(m);
    setSelectedToken(null);
  };

  return (
    <div className="min-h-screen bg-black text-gray-200">
      <SiteHeader />
      <div className="max-w-7xl mx-auto p-6">
        <div className="mt-6 mb-8 flex flex-wrap items-center gap-x-6 gap-y-3">
          <div className="flex items-center gap-2">
            <h1 className="text-3xl font-light text-blue-300">Earn Yield From:</h1>
            <span
              tabIndex={0}
              className="group relative inline-flex items-center justify-center w-5 h-5 rounded-full border border-gray-700 text-gray-500 text-xs cursor-help hover:border-blue-400 hover:text-blue-300 focus:outline-none focus:border-blue-400 focus:text-blue-300"
              aria-label="About earning yield"
            >
              i
              <span
                role="tooltip"
                className="pointer-events-none absolute left-0 top-full mt-2 w-72 p-3 rounded-lg border border-gray-700 bg-black/95 text-xs text-gray-300 shadow-lg opacity-0 invisible group-hover:opacity-100 group-hover:visible group-focus:opacity-100 group-focus:visible transition-opacity z-10"
              >
                Sell fully-collateralized options to collect premium. Your collateral stays yours until
                the option exercises or expires.
              </span>
            </span>
          </div>
          <ModeToggle mode={mode} onChange={handleModeChange} />
        </div>

        {mode === "puts" && (
          <div className="mb-6 p-4 rounded-xl border border-gray-800 bg-black/40">
            <div className="text-xs uppercase tracking-wider text-gray-500 mb-3">Collateral stablecoin</div>
            <StablecoinTabs selected={selectedStable} onSelect={setSelectedStable} />
          </div>
        )}

        <TokenGrid tokens={tokens} selected={selectedToken} onSelect={setSelectedToken} />

        {selected && (
          <div className="mt-6">
            <YieldPanel
              mode={mode}
              token={selected}
              stablecoin={mode === "puts" ? selectedStable : undefined}
              onClose={() => setSelectedToken(null)}
            />
          </div>
        )}
      </div>
      <SiteFooter />
    </div>
  );
}
