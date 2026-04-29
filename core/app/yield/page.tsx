"use client";

import { useState } from "react";
import { SiteFooter } from "../components/SiteFooter";
import { SiteHeader } from "../components/SiteHeader";
import { TokenGrid } from "../components/options/TokenGrid";
import { ModeToggle, type YieldMode } from "./components/ModeToggle";
import { StablecoinTabs } from "./components/StablecoinTabs";
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
      <div className="max-w-7xl mx-auto p-6 flex flex-col items-center text-center">
        {/* Mode toggle (with per-mode tooltips); the page title is in the
            navbar (SiteHeader) — explicit "Earn Yield From" header dropped. */}
        <div className="mt-6 mb-8 w-full flex justify-center">
          <ModeToggle mode={mode} onChange={handleModeChange} />
        </div>

        {mode === "puts" && (
          <div className="mb-6 w-full p-4 rounded-xl border border-gray-800 bg-black/40">
            <div className="text-xs uppercase tracking-wider text-gray-500 mb-3 text-center">
              Collateral stablecoin
            </div>
            <div className="flex justify-center">
              <StablecoinTabs selected={selectedStable} onSelect={setSelectedStable} />
            </div>
          </div>
        )}

        <TokenGrid tokens={tokens} selected={selectedToken} onSelect={setSelectedToken} />

        {selected && (
          // text-center on the wrapper makes the inline-block strike grid
          // (and any other content inside YieldPanel that uses intrinsic
          // width) sit at the page center instead of pinned to the left.
          <div className="mt-6 w-full text-center">
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
