"use client";

import { useState } from "react";
import Navbar from "../mint/components/Navbar";
import { TokenSelector } from "../trade/components/TokenSelector";
import { OptionsGrid } from "./components/OptionsGrid";
import { OptionsTradePanel } from "./components/OptionsTradePanel";
import { useRfqHealth } from "./hooks/useRfqQuote";

export default function OptionsPage() {
  const [selectedToken, setSelectedToken] = useState<string | null>(null);
  const [selectedOption, setSelectedOption] = useState<{
    optionAddress: string;
    strike: bigint;
    expiration: bigint;
    isPut: boolean;
    collateralAddress: string;
    considerationAddress: string;
  } | null>(null);

  // Check RFQ service health
  const { data: health, isLoading: isHealthLoading, error: healthError } = useRfqHealth();

  return (
    <div className="min-h-screen bg-black text-gray-200">
      <div className="max-w-7xl mx-auto p-6">
        <Navbar />
        <h1 className="text-3xl font-light text-blue-300 mb-4 mt-6">Options Trading</h1>
        <p className="text-gray-400 mb-8">RFQ pricing with on-chain settlement via Option contracts</p>

        {/* RFQ Service Status */}
        <div className="mb-6">
          <div
            className={`inline-flex items-center gap-2 px-3 py-1.5 rounded-full text-sm ${
              healthError
                ? "bg-red-900/30 text-red-400 border border-red-700"
                : health
                  ? "bg-green-900/30 text-green-400 border border-green-700"
                  : "bg-yellow-900/30 text-yellow-400 border border-yellow-700"
            }`}
          >
            {isHealthLoading ? (
              <>
                <span className="animate-pulse">●</span> Connecting to RFQ service...
              </>
            ) : healthError ? (
              <>
                <span>●</span> RFQ service offline
              </>
            ) : health ? (
              <>
                <span>●</span> RFQ service online ({health.optionsCount} options)
              </>
            ) : (
              <>
                <span>●</span> Unknown status
              </>
            )}
          </div>
        </div>

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
            <OptionsTradePanel selectedOption={selectedOption} onClose={() => setSelectedOption(null)} />
          </div>
        )}
      </div>
    </div>
  );
}
