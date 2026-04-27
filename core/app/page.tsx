"use client";

import { useEffect, useState } from "react";
import Image from "next/image";
import Link from "next/link";

const SERIF_STACK = "var(--font-instrument-serif), ui-serif, Georgia, serif";
const HERO_LINES: readonly string[] = ["Don't get liquidated", "Earn the Best Yield in DeFi"];
const TYPE_MS = 55;
const LINE_PAUSE_MS = 350;

function TypewriterHero() {
  const [lineIndex, setLineIndex] = useState(0);
  const [chars, setChars] = useState(0);

  useEffect(() => {
    if (lineIndex >= HERO_LINES.length) return;
    const line = HERO_LINES[lineIndex];

    if (chars < line.length) {
      const id = setTimeout(() => setChars(c => c + 1), TYPE_MS);
      return () => clearTimeout(id);
    }

    if (lineIndex < HERO_LINES.length - 1) {
      const id = setTimeout(() => {
        setLineIndex(i => i + 1);
        setChars(0);
      }, LINE_PAUSE_MS);
      return () => clearTimeout(id);
    }
  }, [lineIndex, chars]);

  const renderLine = (idx: number) => {
    if (idx > lineIndex) return "";
    if (idx < lineIndex) return HERO_LINES[idx];
    return HERO_LINES[idx].slice(0, chars);
  };

  const showCaretOn = (idx: number) => {
    if (lineIndex === HERO_LINES.length - 1 && chars >= HERO_LINES[lineIndex].length) return false;
    return idx === lineIndex;
  };

  return (
    <h2
      style={{ fontFamily: SERIF_STACK }}
      className="text-[clamp(2.75rem,8vw,6.5rem)] leading-[1.05] text-white tracking-tight"
    >
      <span className="block">
        {renderLine(0)}
        {showCaretOn(0) && <span className="inline-block w-[0.6ch] -mb-1 animate-pulse text-blue-400">|</span>}
      </span>
      <span className="block bg-linear-to-r from-blue-400 to-blue-600 text-transparent bg-clip-text italic">
        {renderLine(1)}
        {showCaretOn(1) && (
          <span className="inline-block w-[0.6ch] -mb-1 animate-pulse text-blue-400 not-italic">|</span>
        )}
      </span>
    </h2>
  );
}

type NavItem = { label: string; href: string; external?: boolean };

const FOOTER_NAV: NavItem[] = [
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

const HEADER_NAV: NavItem[] = FOOTER_NAV.filter(
  i => !["Contact", "Telegram", "GitHub", "Terms", "Privacy"].includes(i.label),
);

const PILLARS: { heading: string; body: string }[] = [
  {
    heading: "The missing primitive",
    body:
      "Options are the only DeFi primitive that price downside protection without forcing you to sell. " +
      "Insurance when markets crash, leverage when they rip and convexity in both directions.",
  },
  {
    heading: "Composability Required",
    body:
      "An option that can't be transferred, lent, or used as collateral is half a product. Greek options are ERC20: " +
      "trade them on AMMs, post them in money markets, wrap them in vaults. Same building blocks as any other token.",
  },
  {
    heading: "Unlock missing yield",
    body:
      "Selling covered options is the oldest yield in finance and the largest one DeFi still hasn't priced in. " +
      "Stake your assets, write upside, get paid in premium without giving up custody.",
  },
];

export default function OptionsPage() {
  return (
    <div className="min-h-screen bg-black text-gray-200">
      {/* Navbar */}
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
          </div>
        </div>
      </nav>

      {/* Hero */}
      <section className="relative py-32 px-6">
        <div className="max-w-7xl mx-auto">
          <TypewriterHero />
          <div className="mt-12 flex gap-4">
            <Link href="/trade">
              <button className="bg-blue-500 text-black px-8 py-4 rounded-lg font-medium hover:scale-105 transition-transform">
                Trade
              </button>
            </Link>
            <a href="/yield" target="_blank" rel="noopener noreferrer">
              <button className="border border-blue-500 text-blue-500 px-8 py-4 rounded-lg font-medium hover:bg-blue-500/10 transition-all">
                Earn Yield
              </button>
            </a>
          </div>
        </div>
      </section>

      {/* Pillars — title above body, stair-stepping from top-left to bottom-right */}
      <section className="py-24 sm:py-32 px-6 border-y border-gray-800">
        <div className="max-w-7xl mx-auto">

          <div className="grid grid-cols-12 gap-y-20 sm:gap-y-28">
            {PILLARS.map((p, i) => (
              <div
                key={p.heading}
                className={`col-span-12 md:col-span-7 max-w-2xl ${
                  i === 0 ? "md:col-start-1" : i === 1 ? "md:col-start-4" : "md:col-start-6"
                }`}
              >
                <h3
                  style={{ fontFamily: SERIF_STACK }}
                  className="text-3xl sm:text-5xl text-blue-300 italic leading-tight mb-5"
                >
                  {p.heading}
                </h3>
                <p
                  style={{ fontFamily: SERIF_STACK }}
                  className="text-xl sm:text-2xl text-gray-300 leading-snug"
                >
                  {p.body}
                </p>
              </div>
            ))}
          </div>
        </div>
      </section>

      {/* Footer */}
      <footer style={{ fontFamily: SERIF_STACK }} className="py-12 px-6">
        <div className="max-w-7xl mx-auto flex flex-col gap-8">
          <div className="flex flex-wrap items-center gap-x-8 gap-y-3 text-base sm:text-lg">
            {FOOTER_NAV.map(item =>
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
          <div className="pt-6 border-t border-gray-800">
            <p className="text-gray-500">© Greek Fi, Inc. 2026</p>
          </div>
        </div>
      </footer>
    </div>
  );
}
