"use client";

import { useState } from "react";
import { Address } from "viem";
import CreateMany from "./CreateMany";
import ContractDetails from "./Details";
import Navbar from "./Navbar";
import SelectOptionAddress from "./Selector";
import Action from "./action";
import MintActionSimple from "./components/MintActionSimple";
import { useOption } from "./hooks/useOption";
import { useOptions } from "./hooks/useOptions";

function OptionsApp() {
  const [optionAddress, setOptionAddress] = useState<Address | undefined>(undefined);

  // Use new hooks
  const { options } = useOptions();
  const { data: optionDetails } = useOption(optionAddress);

  // Convert options to the format expected by SelectOptionAddress
  const optionList = options.map((opt) => ({
    name: opt.name,
    address: opt.address,
  }));

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
                {/* Keep existing action components for exercise/redeem until Phase 2 */}
                <Action details={optionDetails} action="exercise" />
                {/* Simple Mint with auto-approvals */}
                <MintActionSimple optionAddress={optionAddress} />
                <Action details={optionDetails} action="redeem" />
              </div>
            </div>

            <div className="border rounded-lg overflow-hidden">
              <div className="p-4 bg-gray-800">
                <CreateMany />
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
