"use client";

import clsx from "clsx";
import Image from "next/image";
import { useState } from "react";
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

export function TokenGrid({ tokens, selected, onSelect }: TokenGridProps) {
  const { allTokensMap } = useTokenMap();
  const [expanded, setExpanded] = useState(false);
  // Collapse to logo+symbol pills once a pick is made, unless the user is hovering the row.
  const compact = !!selected && !expanded;
  return (
    <div
      onMouseEnter={() => setExpanded(true)}
      onMouseLeave={() => setExpanded(false)}
      className={clsx(
        "grid gap-2 transition-all",
        compact ? "[grid-template-columns:repeat(auto-fill,minmax(5rem,7rem))]" : "",
      )}
      style={
        compact
          ? undefined
          : { gridTemplateColumns: "repeat(auto-fill, minmax(7rem, 9rem))" }
      }
    >
      {tokens.map(token => {
        const active = selected === token.symbol;
        const address = allTokensMap[token.symbol]?.address;
        return (
          <button
            key={token.symbol}
            type="button"
            onClick={() => onSelect(token.symbol)}
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
            {!compact && (
              <>
                {token.apr && (
                  <span className="text-xs font-semibold text-emerald-300 tabular-nums">
                    {formatAprRange(token.apr)}
                  </span>
                )}
                {address && <CopyAddressButton address={address} />}
              </>
            )}
          </button>
        );
      })}
    </div>
  );
}
