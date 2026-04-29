"use client";

import Image from "next/image";
import Link from "next/link";
import { ConnectButton } from "@rainbow-me/rainbowkit";
import { ChainSelector } from "./ChainSelector";

export const SERIF_STACK = "var(--font-instrument-serif), ui-serif, Georgia, serif";

export type NavItem = { label: string; href: string; external?: boolean };

export const FOOTER_NAV: NavItem[] = [
  { label: "Trade Options", href: "/trade" },
  { label: "Earn Yield", href: "/yield" },
  { label: "Docs", href: "https://docs.greek.fi", external: true },
  { label: "Whitepaper", href: "/greekfi.pdf", external: true },
  { label: "Contact", href: "mailto:hello@greek.fi", external: true },
  { label: "Telegram", href: "https://t.me/greekfi", external: true },
  { label: "GitHub", href: "https://github.com/greekfi", external: true },
  { label: "Terms", href: "#" },
  { label: "Privacy", href: "#" },
];

export const HEADER_NAV: NavItem[] = FOOTER_NAV.filter(
  i => !["Contact", "Telegram", "GitHub", "Terms", "Privacy"].includes(i.label),
);

/**
 * Wallet button rendered via {@link ConnectButton.Custom} so we control the
 * typography (Instrument Serif, regular weight) and which fields show. The
 * default RainbowKit pill renders bold and surfaces an ETH balance we don't
 * want — here we render the ENS-preferring `account.displayName` only.
 */
function WalletButton() {
  const buttonClass =
    "px-3.5 py-2 rounded-lg border border-gray-700 hover:border-blue-300 transition-colors text-lg sm:text-xl";

  return (
    <ConnectButton.Custom>
      {({ account, chain, openAccountModal, openChainModal, openConnectModal, authenticationStatus, mounted }) => {
        const ready = mounted && authenticationStatus !== "loading";
        const connected =
          ready && account && chain && (!authenticationStatus || authenticationStatus === "authenticated");

        return (
          <div
            style={{ fontFamily: SERIF_STACK, fontWeight: 400 }}
            aria-hidden={!ready}
            className={ready ? "" : "opacity-0 pointer-events-none select-none"}
          >
            {!connected && (
              <button onClick={openConnectModal} type="button" className={`${buttonClass} text-blue-300`}>
                Connect Wallet
              </button>
            )}
            {connected && chain.unsupported && (
              <button onClick={openChainModal} type="button" className={`${buttonClass} text-red-400`}>
                Wrong network
              </button>
            )}
            {connected && !chain.unsupported && (
              // Use RainbowKit's native chain pill + modal when connected — it
              // has chain icons and the polished switch-chain UI. Our custom
              // ChainSelector handles the unconnected case (RainbowKit's modal
              // can't open without a wallet).
              <div className="flex gap-2">
                <button
                  onClick={openChainModal}
                  type="button"
                  className={`${buttonClass} text-gray-300 flex items-center gap-1.5`}
                >
                  {chain.hasIcon && chain.iconUrl && (
                    /* eslint-disable-next-line @next/next/no-img-element */
                    <img src={chain.iconUrl} alt={chain.name ?? ""} className="w-4 h-4 rounded-full" />
                  )}
                  <span>{chain.name}</span>
                </button>
                <button onClick={openAccountModal} type="button" className={`${buttonClass} text-gray-200`}>
                  {account.displayName}
                </button>
              </div>
            )}
          </div>
        );
      }}
    </ConnectButton.Custom>
  );
}

interface SiteHeaderProps {
  /** Show the wallet button on the right (default: true). */
  showWallet?: boolean;
}

/**
 * Shared site header used on the home page, /trade, and /yield. Logo + Greek
 * wordmark on the left, primary nav on the right, optional wallet on the far
 * right. All typography is Instrument Serif via the SERIF_STACK CSS variable.
 */
export function SiteHeader({ showWallet = true }: SiteHeaderProps) {
  return (
    <nav className="sticky top-0 z-50 backdrop-blur-sm bg-black/80 border-b border-gray-800">
      <div className="max-w-7xl mx-auto px-4 sm:px-6 py-4">
        <div className="flex flex-col sm:flex-row items-center justify-between gap-4">
          <Link href="/" className="flex items-center gap-3 sm:gap-4 group">
            <Image
              src="/helmet.svg"
              alt="Greek"
              width={64}
              height={64}
              className="h-12 w-12 sm:h-14 sm:w-14"
            />
            <span
              style={{ fontFamily: SERIF_STACK }}
              className="text-3xl sm:text-4xl lg:text-5xl text-white group-hover:text-blue-300 transition-colors"
            >
              Greek
            </span>
          </Link>

          <div className="flex flex-wrap items-center gap-x-6 gap-y-2 sm:gap-x-8">
            <div
              style={{ fontFamily: SERIF_STACK }}
              className="flex flex-wrap items-center gap-x-6 gap-y-2 text-lg sm:text-xl"
            >
              {HEADER_NAV.map(item =>
                item.external ? (
                  <a
                    key={item.label}
                    href={item.href}
                    target="_blank"
                    rel="noopener noreferrer"
                    className="text-gray-300 hover:text-blue-300 transition-colors"
                  >
                    {item.label}
                  </a>
                ) : (
                  <Link
                    key={item.label}
                    href={item.href}
                    className="text-gray-300 hover:text-blue-300 transition-colors"
                  >
                    {item.label}
                  </Link>
                ),
              )}
            </div>
            {showWallet && (
              <div className="flex items-center gap-2">
                <ChainSelector />
                <WalletButton />
              </div>
            )}
          </div>
        </div>
      </div>
    </nav>
  );
}
