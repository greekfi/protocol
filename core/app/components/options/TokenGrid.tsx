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

  // Collapse to logo+symbol pills once a pick is made, unless the user has held
  // the cursor over the row long enough to expand.
  const compact = !!selected && !expanded;
  // Filter to tokens that exist on the current (browse) chain. The static
  // CALL_UNDERLYINGS / PUT_UNDERLYINGS lists in yield/data.ts are the
  // *universe* of supported underlyings; allTokensMap (chain-scoped via
  // useTokenMap) tells us which of those are actually deployed on the
  // chain the user is browsing. e.g. cbBTC is only on Base, MORPHO doesn't
  // have a canonical Arbitrum deployment — those simply don't render.
  const tokensForChain = tokens.filter(t => allTokensMap[t.symbol]?.address);
  // Keep column structure constant — animating grid-template-columns isn't
  // smooth in any browser and reads as a "jump." Cells stay the same width;
  // only the content area inside each cell expands/collapses.
  return (
    <div
      onMouseEnter={onMouseEnter}
      onMouseLeave={onMouseLeave}
      // Flex (not grid) so items center on every row — including a partial
      // last row. Each cell is fixed-width via flex-basis; rows wrap and
      // `justify-center` centers items on each line, which CSS grid won't
      // do reliably when the container width is much greater than the
      // total cell width.
      // `mx-auto w-fit max-w-full` — shrink-wrap to content width and center
      // the whole grid in its parent. Without this, a flex container as a
      // child of another flex layout takes full width and the grid sits
      // left-aligned in a too-wide column.
      className="flex flex-wrap justify-center gap-2 mx-auto w-fit max-w-full"
    >
      {tokensForChain.map(token => {
        const active = selected === token.symbol;
        const address = allTokensMap[token.symbol]?.address;
        return (
          <button
            key={token.symbol}
            type="button"
            onClick={() => onSelect(token.symbol)}
            // basis 7.5rem, no grow/shrink — cells are uniform width and
            // wrap predictably regardless of container width.
            style={{ flex: "0 0 7.5rem" }}
            className={clsx(
              "flex flex-col items-start gap-1 px-3 py-2 rounded-lg border text-left transition-colors",
              active
                ? "bg-[#2F50FF]/15 border-[#2F50FF]"
                : "bg-black/40 border-gray-800 hover:border-gray-700 hover:bg-black/60",
            )}
          >
            <div className="flex items-center gap-2">
              <Logo token={token} size={22} />
              <span className="text-sm font-semibold text-blue-200 truncate">{token.symbol}</span>
            </div>
            {/* Always render the extras; toggle visibility via opacity +
                grid-template-rows so the cell height animates smoothly.
                grid-template-rows from 0fr → 1fr is the modern way to animate
                "auto" height — works in all evergreen browsers. */}
            <div
              className={clsx(
                "grid w-full transition-[grid-template-rows,opacity] duration-300 ease-out",
                compact ? "grid-rows-[0fr] opacity-0" : "grid-rows-[1fr] opacity-100",
              )}
              aria-hidden={compact}
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
      })}
    </div>
  );
}
