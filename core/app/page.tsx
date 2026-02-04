"use client";

import Image from "next/image";
import Link from "next/link";
import Helmet from "~~/public/helmet-white.svg";

export default function OptionsPage() {
  return (
    <div className="min-h-screen bg-black text-gray-200">
      <div className="min-h-screen bg-black">
        {/* Navbar */}
        <nav className="sticky top-0 z-50 backdrop-blur-sm bg-black/80 border-b border-gray-800">
          <div className="max-w-7xl mx-auto px-4 sm:px-6 py-4">
            <div className="flex flex-col sm:flex-row items-center justify-between gap-4">
              {/* Logo and Title */}
              <div className="flex items-center gap-3 sm:gap-4">
                <Image src={Helmet} alt="Greek.fi Logo" className="h-16 w-16 sm:h-20 sm:w-20 lg:h-24 lg:w-24" />
                <h1 className="text-2xl sm:text-3xl lg:text-4xl text-blue-300 font-(--font-martel-sans)">GreekFi</h1>
              </div>

              {/* Navigation Buttons */}
              <div className="flex items-center gap-2 sm:gap-3">
                <Link href="/mint">
                  <button className="hover:scale-105 transition-transform bg-blue-300 text-black px-4 py-2 rounded-lg font-medium text-sm sm:text-base">
                    Mint
                  </button>
                </Link>
                <button className="hover:scale-105 transition-transform bg-blue-500 text-black px-4 py-2 rounded-lg font-medium text-sm sm:text-base">
                  Trade Soon
                </button>
                <button className="hover:scale-105 transition-transform bg-blue-100 text-black px-4 py-2 rounded-lg font-medium text-sm sm:text-base">
                  Vault Soon
                </button>
              </div>
            </div>
          </div>
        </nav>

        {/* Hero Section */}
        <section className="relative py-32 px-6">
          <div className="max-w-7xl mx-auto">
            {/* <div className="absolute inset-0 bg-linear-to-r from-blue-500/10 to-purple-500/10 blur-3xl"></div> */}
            <h2 className="text-[clamp(2.5rem,8vw,6rem)] font-bold text-white leading-tight">
              The only options protocol <br />
              <span className="bg-linear-to-r from-blue-400 to-blue-600 text-transparent bg-clip-text">
                built for defi
              </span>
            </h2>
            <p className="mt-6 text-gray-400 text-xl max-w-2xl">
              Mint, trade, and vault your options. No oracle needed. Full collateralization.
            </p>
            <div className="mt-12 flex gap-4">
              <button className="bg-blue-500 text-black px-8 py-4 rounded-lg font-medium hover:scale-105 transition-transform">
                Start Trading Soon
              </button>
              <a href="/greekfi.pdf" target="_blank" rel="noopener noreferrer">
                <button className="border border-blue-500 text-blue-500 px-8 py-4 rounded-lg font-medium hover:bg-blue-500/10 transition-all">
                  Read the Whitepaper
                </button>
              </a>
            </div>
          </div>
        </section>

        {/* Feature Grid with Original Color Scheme */}
        <section className="py-16 px-6 border-y border-gray-800">
          <div className="max-w-7xl mx-auto">
            <h2 className="text-4xl font-bold text-white mb-12 text-center">Why Choose Greek.fi?</h2>

            <div className="grid grid-cols-1 md:grid-cols-3 gap-8">
              {/* Collateral Card */}
              <div className="p-8 rounded-2xl bg-linear-to-br from-blue-500/20 to-blue-400/20 border border-blue-500/20 hover:border-blue-500/40 transition-all">
                <div className="h-12 w-12 bg-blue-500/20 rounded-full flex items-center justify-center mb-6">
                  <span className="text-2xl">💎</span>
                </div>
                <h3 className="text-xl font-bold text-blue-400 mb-3">Any ERC20 Collateral</h3>
                <p className="text-gray-400">
                  Use any token as collateral, including staked tokens still earning yield! stETH, sBTC, and more.
                </p>
              </div>

              {/* Token System Card */}
              <div className="p-8 rounded-2xl bg-linear-to-br from-blue-400/20 to-blue-300/20 border border-blue-400/20 hover:border-blue-400/40 transition-all">
                <div className="h-12 w-12 bg-blue-400/20 rounded-full flex items-center justify-center mb-6">
                  <span className="text-2xl">🎯</span>
                </div>
                <h3 className="text-xl font-bold text-blue-300 mb-3">Dual Token System</h3>
                <p className="text-gray-400">
                  Get LONG tokens for American-style exercise rights and SHORT tokens for post-expiration redemption.
                </p>
              </div>

              {/* Trading Card */}
              <div className="p-8 rounded-2xl bg-linear-to-br from-blue-300/20 to-blue-200/20 border border-blue-300/20 hover:border-blue-300/40 transition-all">
                <div className="h-12 w-12 bg-blue-300/20 rounded-full flex items-center justify-center mb-6">
                  <span className="text-2xl">📈</span>
                </div>
                <h3 className="text-xl font-bold text-blue-200 mb-3">Fully Tradable</h3>
                <p className="text-gray-400">Trade options via RFQ partners 0x and Bebop with zero slippage.</p>
              </div>
            </div>

            {/* Additional Benefits */}
            <div className="grid grid-cols-1 md:grid-cols-3 gap-8 mt-8">
              <div className="p-8 rounded-2xl bg-linear-to-br from-blue-500/20 to-blue-400/20 border border-blue-500/20 hover:border-blue-500/40 transition-all">
                <div className="h-12 w-12 bg-blue-500/20 rounded-full flex items-center justify-center mb-6">
                  <span className="text-2xl">🛡️</span>
                </div>
                <h3 className="text-xl font-bold text-blue-400 mb-3">Risk Protected</h3>
                <p className="text-gray-400">No oracle needed. No margin. No counterparty risk.</p>
              </div>

              <div className="p-8 rounded-2xl bg-linear-to-br from-blue-400/20 to-blue-300/20 border border-blue-400/20 hover:border-blue-400/40 transition-all">
                <div className="h-12 w-12 bg-blue-400/20 rounded-full flex items-center justify-center mb-6">
                  <span className="text-2xl">⚡</span>
                </div>
                <h3 className="text-xl font-bold text-blue-300 mb-3">Easy Exercise</h3>
                <p className="text-gray-400">
                  Exercise anytime before expiration with LONG tokens. Redeem after expiration with SHORT tokens.
                </p>
              </div>

              <div className="p-8 rounded-2xl bg-linear-to-br from-blue-300/20 to-blue-200/20 border border-blue-300/20 hover:border-blue-300/40 transition-all">
                <div className="h-12 w-12 bg-blue-300/20 rounded-full flex items-center justify-center mb-6">
                  <span className="text-2xl">📊</span>
                </div>
                <h3 className="text-xl font-bold text-blue-200 mb-3">Yield Vaults</h3>
                <p className="text-gray-400">
                  Earn yield through covered options. We handle the selling and market making.
                </p>
              </div>
            </div>
          </div>
        </section>

        {/* Feature Blocks */}
        <section className="grid grid-cols-1 md:grid-cols-3 gap-1 py-20">
          <div className="bg-blue-400 p-12 hover:scale-[1.02] transition-transform">
            <h3 className="text-4xl font-bold text-black mb-4">Mint Options</h3>
            <p className="text-black/80 mb-6">Create fully-collateralized options with any ERC20 token</p>
            <Link href="/mint">
              <button className="bg-black text-white px-6 py-3 rounded-lg hover:bg-gray-900">Start Minting →</button>
            </Link>
          </div>
          <div className="bg-blue-500 p-12 hover:scale-[1.02] transition-transform">
            <h3 className="text-4xl font-bold text-black mb-4">Trade Soon</h3>
            <p className="text-black/80 mb-6">Buy and sell options with zero slippage using RFQ systems</p>
            <button className="bg-black text-white px-6 py-3 rounded-lg hover:bg-gray-900">Trade Soon →</button>
          </div>
          <div className="bg-blue-300 p-12 hover:scale-[1.02] transition-transform">
            <h3 className="text-4xl font-bold text-black mb-4">Option Vaults Soon</h3>
            <p className="text-black/80 mb-6">Automate your covered call strategies</p>
            <button className="bg-black text-white px-6 py-3 rounded-lg hover:bg-gray-900">Vault Soon →</button>
          </div>
        </section>

        {/* Integration Partners */}
        {/* <section className="py-20 px-6 border-t border-gray-800">
        <div className="max-w-7xl mx-auto">
          <h3 className="text-center text-gray-400 mb-12">Integrated with</h3>
          <div className="grid grid-cols-2 md:grid-cols-4 gap-8 opacity-50">
            {/* Add partner logos here */}
        {/* <div className="h-12 bg-gray-800 rounded"></div>
            <div className="h-12 bg-gray-800 rounded"></div>
            <div className="h-12 bg-gray-800 rounded"></div>
            <div className="h-12 bg-gray-800 rounded"></div>
          </div>
        </div>
      </section> */}

        {/* Footer */}
        <footer className="border-t border-gray-800 py-12 px-6">
          <div className="max-w-7xl mx-auto">
            <div className="grid grid-cols-1 md:grid-cols-4 gap-12 mb-12">
              <div>
                <div className="flex items-center gap-4 mb-4">
                  <Image src={Helmet} alt="Greek.fi Logo" className="h-8 w-8" />
                  <h3 className="text-xl font-light text-blue-300">Greek.fi</h3>
                </div>
                <p className="text-gray-400">The future of decentralized options trading</p>
              </div>
              <div>
                <h4 className="text-white font-bold mb-4">Protocol</h4>
                <ul className="space-y-2">
                  <li>
                    <Link href="#" className="text-gray-400 hover:text-blue-300">
                      Trade (Soon)
                    </Link>
                  </li>
                  <li>
                    <Link href="/mint" className="text-gray-400 hover:text-blue-300">
                      Mint/Send
                    </Link>
                  </li>
                  <li>
                    <Link href="#" className="text-gray-400 hover:text-blue-300">
                      Vault (Soon)
                    </Link>
                  </li>
                </ul>
              </div>
              <div>
                <h4 className="text-white font-bold mb-4">Resources</h4>
                <ul className="space-y-2">
                  <li>
                    <a href="/greekfi.pdf" className="text-gray-400 hover:text-blue-300">
                      Whitepaper
                    </a>
                  </li>
                  <li>
                    <a href="https://github.com/greekfi" className="text-gray-400 hover:text-blue-300">
                      GitHub
                    </a>
                  </li>
                  {/* <li><a href="https://docs.greek.fi" className="text-gray-400 hover:text-blue-300">Docs</a></li> */}
                </ul>
              </div>
              <div>
                <h4 className="text-white font-bold mb-4">Community</h4>
                <ul className="space-y-2">
                  <li>
                    <a href="https://discord.gg/3saJeJ6MeE" className="text-gray-400 hover:text-blue-300">
                      Discord
                    </a>
                  </li>
                  <li>
                    <a href="https://x.com/greekdotfi" className="text-gray-400 hover:text-blue-300">
                      Twitter
                    </a>
                  </li>
                  <li>
                    <a href="https://t.me/greekfi" className="text-gray-400 hover:text-blue-300">
                      Telegram
                    </a>
                  </li>
                </ul>
              </div>
            </div>
            <div className="border-t border-gray-800 pt-8 flex justify-between items-center">
              <p className="text-gray-500">© Greek Fi LLC, 2025</p>
              <div className="flex gap-6">
                <a href="#" className="text-gray-400 hover:text-blue-300">
                  Terms
                </a>
                <a href="#" className="text-gray-400 hover:text-blue-300">
                  Privacy
                </a>
              </div>
            </div>
          </div>
        </footer>
      </div>
    </div>
  );
}
