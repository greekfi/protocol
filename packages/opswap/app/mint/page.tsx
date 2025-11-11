"use client";

import { useState } from "react";
import CreateMany from "./CreateMany";
import ContractDetails from "./Details";
import Navbar from "./Navbar";
import SelectOptionAddress from "./Selector";
import Action from "./action";
import { useOptionDetails } from "./hooks/useGetOption";
import { useGetOptions } from "./hooks/useGetOptions";
import { Address } from "viem";

function OptionsApp() {
  const [optionAddress, setOptionAddress] = useState<Address>("0x0");
  const { refetch, optionList } = useGetOptions();
  const contractDetails = useOptionDetails(optionAddress);

  return (
    <div className="min-h-screen bg-black text-gray-200">
      <main className="flex-1">
        <div className="flex flex-col gap-6 max-w-7xl mx-auto p-6">
          <Navbar />
          <ContractDetails details={contractDetails} />
          <div className="space-y-2">
            <div className="border rounded-lg overflow-hidden">
              <div className="p-4 bg-gray-800">
                <SelectOptionAddress setOptionAddress={setOptionAddress} optionList={optionList} />
              </div>

              <div className="grid grid-cols-1 md:grid-cols-3 gap-4 p-4 bg-gray-800">
                <Action details={contractDetails} action="exercise" />
                <Action details={contractDetails} action="mint" />
                <Action details={contractDetails} action="redeem" />
              </div>
            </div>

            <div className="border rounded-lg overflow-hidden">
              <div className="p-4 bg-gray-800">
                <CreateMany refetchOptions={refetch} />
              </div>
            </div>
          </div>
        </div>

        <footer className="py-8 px-6 text-gray-200 bg-gray-700">
          <div id="about">
            {/* <p className="text-gray-200">
              Greek.fi provides the only option protocol on chain that collateralizes any
            ERC20 token to a redeemable token and provides a fully on-chain option that is exercisable.
            Both the collateral and the option are ERC20 tokens.
            </p> */}
          </div>
          <span className="text-gray-500">Greek.fi © 2025</span>
        </footer>
      </main>
    </div>
  );
}

export default function MintPage() {
  return <OptionsApp />;
}
