"use client";

import { useState } from "react";
import Image from "next/image";
import Link from "next/link";
import logo from "../../public/helmet-white.svg";
import Deploy from "./Deploy";
import ContractDetails from "./Details";
import SelectOptionAddress from "./Selector";
import { Account } from "./account";
import Action from "./action";
import { WalletSelector } from "./components/walletSelector";
import { useOptionDetails } from "./hooks/details";
import { Address } from "viem";
import { useAccount, useConfig } from "wagmi";

function ConnectWallet() {
  const { isConnected } = useAccount();
  if (isConnected) return <Account />;
  return <WalletSelector />;
}

function OptionsApp() {
  const [optionAddress, setOptionAddress] = useState<Address>("0x0");
  const contractDetails = useOptionDetails(optionAddress);
  const wagmiConfig = useConfig();
  console.log("chain", wagmiConfig);

  return (
    <div className="min-h-screen bg-black text-gray-200">
      <main className="flex-1">
        <div className="flex flex-col gap-6 max-w-7xl mx-auto p-6">
          <nav className="flex justify-between w-full">
            <ul className="flex items-center space-x-6">
              <li>
                <Image src={logo} alt="Greek.fi" className="w-24 h-24" />
              </li>
              <li>
                <Link href="/packages/nextjs/public" className="hover:text-blue-500">
                  About GreekFi
                </Link>
              </li>
              <li>
                <Link href="https://github.com/greekfi/whitepaper" className="hover:text-blue-500">
                  Whitepaper
                </Link>
              </li>
              <li>
                <Link href="mailto:hello@greek.fi" className="hover:text-blue-500 text-blue-300">
                  Contact
                </Link>
              </li>
              <li>
                <ConnectWallet />
              </li>
            </ul>
          </nav>

          <div>
            <ContractDetails details={contractDetails} />
          </div>

          <div className="space-y-2">
            <div className="border rounded-lg overflow-hidden">
              <div className="p-4 bg-gray-800">
                <SelectOptionAddress setOptionAddress={setOptionAddress} />
              </div>

              <div className="grid grid-cols-1 md:grid-cols-3 gap-4 p-4 bg-gray-800">
                <Action details={contractDetails} action="exercise" />
                <Action details={contractDetails} action="mint" />
                <Action details={contractDetails} action="redeem" />
              </div>
            </div>

            <div className="border rounded-lg overflow-hidden">
              <div className="p-4 bg-gray-800">
                <Deploy />
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
