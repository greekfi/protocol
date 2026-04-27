"use client";

import Image from "next/image";
import Link from "next/link";
import { ConnectButton } from "@rainbow-me/rainbowkit";

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

interface SiteHeaderProps {
  /** Show the wallet ConnectButton on the right (default: true). */
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
              className="flex flex-wrap items-center gap-x-6 gap-y-2 text-base sm:text-lg"
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
            {showWallet && <ConnectButton />}
          </div>
        </div>
      </div>
    </nav>
  );
}
