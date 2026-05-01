"use client";

import clsx from "clsx";
import Image from "next/image";
import { useEffect, useRef, useState } from "react";
import { useTokenMap } from "../../mint/hooks/useTokenMap";

// ===== Types and helpers (shared by /yield and /trade) =====

export type AprRange = { min: number; max: number };

export type UnderlyingToken = {
  symbol: string;
  name: string;
  /** Tailwind bg-* class used as a fallback colour when the token logo PNG is missing. */
  color: string;
  /** Optional yield estimate; rendered as a green badge when present. /trade omits it. */
  apr?: AprRange;
};

export function formatAprRange(apr?: AprRange): string {
  if (!apr) return "";
  return apr.min === apr.max ? `${apr.min}%` : `${apr.min}–${apr.max}%`;
}

// ===== TokenGrid component =====

interface TokenGridProps {
  tokens: UnderlyingToken[];
  selected: string | null;
  onSelect: (symbol: string) => void;
}

function Logo({ token, size = 28 }: { token: UnderlyingToken; size?: number }) {
  const [errored, setErrored] = useState(false);
  if (errored) {
    return (
      <span
        className={clsx(
          "inline-flex items-center justify-center rounded-full font-semibold text-white shrink-0",
          token.color,
        )}
        style={{ width: size, height: size, fontSize: size * 0.42 }}
      >
        {token.symbol[0]}
      </span>
    );
  }
  return (
    <Image
      src={`/tokens/${token.symbol.toLowerCase()}.png`}
      alt={token.symbol}
      width={size}
      height={size}
      className="rounded-full shrink-0"
      onError={() => setErrored(true)}
    />
  );
}

function shorten(addr?: string) {
  if (!addr) return "";
  return `${addr.slice(0, 6)}…${addr.slice(-4)}`;
}

function CopyAddressButton({ address }: { address: string }) {
  const [copied, setCopied] = useState(false);
  const handle = (e: React.MouseEvent) => {
    e.stopPropagation();
    navigator.clipboard
      .writeText(address)
      .then(() => {
        setCopied(true);
        setTimeout(() => setCopied(false), 1000);
      })
      .catch(() => {});
  };
  return (
    <button
      type="button"
      onClick={handle}
      className="inline-flex items-center gap-1 text-[10px] font-mono text-gray-500 hover:text-[#35F3FF] transition-colors"
      title={address}
    >
      <span>{shorten(address)}</span>
      <span className="text-gray-600" aria-hidden>
        {copied ? "✓" : "⧉"}
      </span>
    </button>
  );
}

// Hover-to-expand timing.
//   ENTER_DELAY: how long the cursor must rest before the grid expands.
//     500ms feels deliberate without blocking — common pattern for
//     hover-expand panels (Material uses 300-500ms; macOS Dock ≈ 350ms).
//   LEAVE_DELAY: small grace window before collapsing so quick re-entries
//     (e.g. mouse jitter, crossing a gap) don't flicker.
const ENTER_DELAY = 500;
const LEAVE_DELAY = 150;

export function TokenGrid({ tokens, selected, onSelect }: TokenGridProps) {
  const { allTokensMap } = useTokenMap();
  const [expanded, setExpanded] = useState(false);
  const enterTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const leaveTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  const clearTimers = () => {
    if (enterTimerRef.current) clearTimeout(enterTimerRef.current);
    if (leaveTimerRef.current) clearTimeout(leaveTimerRef.current);
    enterTimerRef.current = null;
    leaveTimerRef.current = null;
  };

  const onMouseEnter = () => {
    clearTimers();
    enterTimerRef.current = setTimeout(() => setExpanded(true), ENTER_DELAY);
  };
  const onMouseLeave = () => {
    clearTimers();
    leaveTimerRef.current = setTimeout(() => setExpanded(false), LEAVE_DELAY);
  };
  // Clean up on unmount so a stray timer doesn't fire after the grid is gone.
  useEffect(() => () => clearTimers(), []);

  // Filter to tokens that exist on the current (browse) chain. The static
  // CALL_UNDERLYINGS / PUT_UNDERLYINGS lists in yield/data.ts are the
  // *universe* of supported underlyings; allTokensMap (chain-scoped via
  // useTokenMap) tells us which of those are actually deployed on the
  // chain the user is browsing. e.g. cbBTC is only on Base, MORPHO doesn't
  // have a canonical Arbitrum deployment — those simply don't render.
  const tokensForChain = tokens.filter(t => allTokensMap[t.symbol]?.address);

  // Three render states:
  //   1. No selection         → full grid inline (initial picker).
  //   2. Selected, collapsed  → just the selected pill + chevron.
  //   3. Selected, expanded   → selected pill stays inline, full list
  //                             renders as a floating overlay so the
  //                             surrounding layout doesn't shift.
  const compact = !!selected && !expanded;
  const inlineTokens = selected ? tokensForChain.filter(t => t.symbol === selected) : tokensForChain;
  const showOverlay = !!selected && expanded;

  const renderPill = (token: UnderlyingToken, opts: { isAnchor: boolean; collapsedExtras: boolean }) => {
    const active = selected === token.symbol;
    const address = allTokensMap[token.symbol]?.address;
    const handleClick = () => {
      if (opts.isAnchor && active && compact) {
        // Anchor pill in compact mode acts as the dropdown trigger.
        setExpanded(true);
      } else {
        onSelect(token.symbol);
        setExpanded(false);
      }
    };
    return (
      <button
        key={token.symbol}
        type="button"
        onClick={handleClick}
        style={{ flex: "0 0 7.5rem" }}
        className={clsx(
          "flex flex-col items-start gap-1 px-3 py-2 rounded-lg border text-left transition-colors",
          active
            ? "bg-black/60 border-gray-600"
            : "bg-black/40 border-gray-800 hover:border-gray-700 hover:bg-black/60",
        )}
      >
        <div className="flex items-center gap-2 w-full">
          <Logo token={token} size={22} />
          <span className="text-sm font-semibold text-blue-200 truncate">{token.symbol}</span>
          {opts.isAnchor && active && compact && (
            <svg
              className="ml-auto text-gray-400"
              width="12"
              height="12"
              viewBox="0 0 12 12"
              fill="none"
              aria-hidden
            >
              <path d="M3 4.5L6 7.5L9 4.5" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" />
            </svg>
          )}
        </div>
        <div
          className={clsx(
            "grid w-full transition-[grid-template-rows,opacity] duration-300 ease-out",
            opts.collapsedExtras ? "grid-rows-[0fr] opacity-0" : "grid-rows-[1fr] opacity-100",
          )}
          aria-hidden={opts.collapsedExtras}
        >
          <div className="overflow-hidden flex flex-col items-start gap-1">
            {token.apr && (
              <span className="text-xs font-semibold text-emerald-300 tabular-nums">
                {formatAprRange(token.apr)}
              </span>
            )}
            {address && <CopyAddressButton address={address} />}
          </div>
        </div>
      </button>
    );
  };

  const selectedToken = selected ? tokensForChain.find(t => t.symbol === selected) : undefined;
  const overlayTokens = selectedToken
    ? [selectedToken, ...tokensForChain.filter(t => t.symbol !== selected)]
    : tokensForChain;

  return (
    <div onMouseEnter={onMouseEnter} onMouseLeave={onMouseLeave}>
      {/* Anchor row — centered. When nothing is selected this is the full
          picker; once a token is picked, only the chosen pill stays inline.
          The inner `relative` wrapper is sized to the pill itself so the
          overlay anchors to the pill's edge, not the card's. */}
      <div className="flex justify-center">
        <div className="relative">
          {/* The inline pill stays in the DOM (so it reserves layout space
              and the buy card doesn't reflow) but is hidden while the
              overlay is open — the overlay's first cell takes its place
              visually. */}
          <div
            className={clsx(
              "flex flex-wrap justify-center gap-2 w-fit max-w-full",
              showOverlay && "invisible",
            )}
          >
            {inlineTokens.map(token => renderPill(token, { isAnchor: true, collapsedExtras: compact }))}
          </div>

          {/* Floating overlay — bordered card that contains the full token
              row, selected pill first, so it reads as a single grouped
              dropdown. -top-2 / -left-2 cancels the card's px-2/py-2
              padding so the first overlay cell sits exactly where the
              hidden inline pill was. */}
          {showOverlay && (
            <div className="absolute -top-2 -left-2 z-30 rounded-xl border border-gray-700 bg-black/95 px-2 py-2 shadow-2xl backdrop-blur-sm">
              <div className="flex flex-nowrap gap-2">
                {overlayTokens.map(token => renderPill(token, { isAnchor: false, collapsedExtras: false }))}
              </div>
            </div>
          )}
        </div>
      </div>
    </div>
  );
}
