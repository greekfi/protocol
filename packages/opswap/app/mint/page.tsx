"use client";

import { useState } from "react";
import { Address } from "viem";
import Create from "./components/Create";
import ContractDetails from "./components/Details";
import Navbar from "./components/Navbar";
import SelectOptionAddress from "./components/Selector";
import Mint from "./components/Mint";
import Exercise from "./components/Exercise";
import Redeem from "./components/Redeem";
import RedeemRedemption from "./components/RedeemRedemption";
import TransferOption from "./components/TransferOption";
import TransferRedemption from "./components/TransferRedemption";
import { useOption } from "./hooks/useOption";
import { useOptions } from "./hooks/useOptions";

function OptionsApp() {
  const [optionAddress, setOptionAddress] = useState<Address | undefined>(undefined);

  // Use new hooks
  const { optionList } = useOptions();
  const { data: optionDetails } = useOption(optionAddress);


  return (
    <div className="min-h-screen bg-black text-gray-200">
      <main className="flex-1">
        <div className="flex flex-col gap-6 max-w-7xl mx-auto p-6">
          <Navbar />
          <ContractDetails details={optionDetails} />
          <div className="space-y-2">
            <div className="border rounded-lg overflow-hidden">
              <div className="p-4 bg-gray-800">
                <SelectOptionAddress
                  setOptionAddress={(addr) => setOptionAddress(addr as Address)}
                  optionList={optionList}
                />
              </div>

              <div className="grid grid-cols-1 md:grid-cols-3 gap-4 p-4 bg-gray-800">
                {/* Clean components - logic in component, hooks are just data/transactions */}
                <Exercise optionAddress={optionAddress} />
                <Mint optionAddress={optionAddress} />
                <Redeem optionAddress={optionAddress} />
              </div>
            </div>

            <div className="border rounded-lg overflow-hidden">
              <div className="grid grid-cols-1 md:grid-cols-3 gap-4 p-4 bg-gray-800">
                <TransferOption optionAddress={optionAddress} />
                <TransferRedemption optionAddress={optionAddress} />
                <RedeemRedemption optionAddress={optionAddress} />
              </div>
            </div>

            <div className="border rounded-lg overflow-hidden">
              <div className="p-4 bg-gray-800">
                <Create />
              </div>
            </div>
          </div>
        </div>

        <footer className="py-8 px-6 text-gray-200 bg-gray-700">
          <div id="about"></div>
          <span className="text-gray-500">Greek.fi © 2025</span>
        </footer>
      </main>
    </div>
  );
}

export default function MintPage() {
  return <OptionsApp />;
}
