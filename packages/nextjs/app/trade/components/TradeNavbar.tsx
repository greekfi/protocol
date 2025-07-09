"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { WalletSelector } from "../../shared/components/walletSelector";

export default function TradeNavbar() {
  const pathname = usePathname();

  return (
    <nav className="bg-gray-900 border-b border-gray-700">
      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
        <div className="flex justify-between h-16">
          <div className="flex items-center">
            <div className="flex-shrink-0">
              <h1 className="text-xl font-bold text-white">Greek.fi</h1>
            </div>
            <div className="ml-10 flex items-baseline space-x-4">
              <Link
                href="/mint"
                className={`px-3 py-2 rounded-md text-sm font-medium ${
                  pathname === "/mint" ? "bg-gray-800 text-white" : "text-gray-300 hover:text-white hover:bg-gray-700"
                }`}
              >
                Mint
              </Link>
              <Link
                href="/trade"
                className={`px-3 py-2 rounded-md text-sm font-medium ${
                  pathname === "/trade" ? "bg-gray-800 text-white" : "text-gray-300 hover:text-white hover:bg-gray-700"
                }`}
              >
                Trade
              </Link>
            </div>
          </div>
          <div className="flex items-center">
            <WalletSelector />
          </div>
        </div>
      </div>
    </nav>
  );
}
