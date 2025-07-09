"use client";

import { useState } from "react";
import { useOptionDetails } from "../shared/hooks/useGetDetails";
import { OptionData } from "../shared/hooks/useGetOptionsByPair";
import { OptionPair } from "../shared/hooks/useGetPairs";
import OptionSelector from "./components/OptionSelector";
import PairSelector from "./components/PairSelector";
import TradeInterface from "./components/TradeInterface";
import TradeNavbar from "./components/TradeNavbar";
import { Address } from "viem";
import { useConfig } from "wagmi";

function TradeApp() {
  const [selectedPair, setSelectedPair] = useState<OptionPair | null>(null);
  const [optionAddress, setOptionAddress] = useState<Address>("0x0");
  const [selectedOption] = useState<OptionData | undefined>(undefined);

  const contractDetails = useOptionDetails(optionAddress);
  const wagmiConfig = useConfig();
  console.log("chain", wagmiConfig);

  return (
    <div className="min-h-screen bg-black text-gray-200">
      <main className="flex-1">
        <div className="flex flex-col gap-6 max-w-7xl mx-auto p-6">
          <TradeNavbar />

          <div className="space-y-6">
            {/* Pair Selector */}
            <div className="border rounded-lg overflow-hidden">
              <div className="p-4 bg-gray-800">
                <PairSelector selectedPair={selectedPair} onPairSelect={setSelectedPair} />
              </div>
            </div>

            {/* Option Selector and Trade Interface */}
            <div className="border rounded-lg overflow-hidden">
              <div className="p-4 bg-gray-800">
                <OptionSelector
                  setOptionAddress={setOptionAddress}
                  selectedOption={selectedOption}
                  selectedPair={selectedPair}
                />
              </div>

              <div className="p-4 bg-gray-800">
                <TradeInterface details={contractDetails} />
              </div>
            </div>
          </div>
        </div>

        <footer className="py-8 px-6 text-gray-200 bg-gray-700">
          <div id="about">
            <p className="text-gray-200">
              Trade options on Greek.fi - The only option protocol that collateralizes any ERC20 token.
            </p>
          </div>
          <span className="text-gray-500">Greek.fi © 2025</span>
        </footer>
      </main>
    </div>
  );
}

export default function TradePage() {
  return <TradeApp />;
}
