"use client";

import { formatUnits } from "viem";
import { useTokenMap } from "../../mint/hooks/useTokenMap";
import { type HeldOption, useAllHeldOptions } from "../../trade/hooks/useAllHeldOptions";
import { BuyBackRow } from "../../components/options/BuyBackButton";

function formatStrike(strike: bigint, isPut: boolean): string {
  const raw = isPut && strike > 0n ? 10n ** 36n / strike : strike;
  const n = Number(formatUnits(raw, 18));
  if (!Number.isFinite(n)) return "—";
  if (n >= 1000) return n.toLocaleString(undefined, { maximumFractionDigits: 0 });
  return n.toLocaleString(undefined, { maximumFractionDigits: 2 });
}

function formatExpiry(exp: bigint): string {
  return new Date(Number(exp) * 1000).toLocaleDateString(undefined, {
    month: "short",
    day: "numeric",
    timeZone: "UTC",
  });
}

function formatAmount(raw: bigint, decimals: number): string {
  const n = Number(formatUnits(raw, decimals));
  if (n === 0) return "0";
  if (n >= 1) return n.toLocaleString(undefined, { maximumFractionDigits: 2 });
  if (n >= 0.0001) return n.toFixed(4);
  return n.toPrecision(2);
}

interface PositionsCardProps {
  /** Click a row → emit the position back so the parent can load it
   *  into the action panel. */
  onSelect?: (h: HeldOption) => void;
  /** Render without the outer rounded-card chrome (used inside another card). */
  bare?: boolean;
  /** Return null entirely when there are no open writes. */
  hideEmpty?: boolean;
}

/**
 * Open-write list for /yield. Filters useAllHeldOptions to receipt > 0
 * (positions where the user is short) and renders each as a 3-line card
 * with an inline buy-back row.
 */
export function PositionsCard({ onSelect, bare = false, hideEmpty = false }: PositionsCardProps) {
  const { held, isLoading, hasWallet } = useAllHeldOptions();
  const { tokensByAddress } = useTokenMap();

  const shorts = held.filter(h => h.receiptBalance > 0n);
  if (hideEmpty && shorts.length === 0) return null;

  const renderRow = (h: HeldOption) => {
    const underlyingAddr = h.isPut ? h.consideration : h.collateral;
    const symbol = tokensByAddress[underlyingAddr.toLowerCase()]?.symbol ?? `${underlyingAddr.slice(0, 6)}…`;
    const decimals = tokensByAddress[h.collateral.toLowerCase()]?.decimals ?? 18;
    const styleCode = h.isEuro ? "E" : "A";
    const sideCode = h.isPut ? "P" : "C";

    return (
      <li
        key={h.option}
        className="block rounded-md border border-gray-800/80 bg-black/30 px-2 py-1.5 hover:border-gray-700 transition-colors"
      >
        <button
          type="button"
          onClick={() => onSelect?.(h)}
          className="w-full text-left"
        >
          <div className="flex items-baseline justify-between gap-2 tabular-nums">
            <span className="truncate text-gray-100">
              {symbol} {formatStrike(h.strike, h.isPut)}
            </span>
            <span className="text-gray-300 shrink-0">−{formatAmount(h.receiptBalance, decimals)}</span>
          </div>
          <div className="text-gray-500 text-[11px] tabular-nums">
            {formatExpiry(h.expiration)} · {sideCode} · {styleCode}
          </div>
        </button>
        <div className="mt-1 pt-1 border-t border-gray-800/60">
          <BuyBackRow
            optionAddress={h.option as `0x${string}`}
            shortAmount={h.receiptBalance}
          />
        </div>
      </li>
    );
  };

  const body = (
    <>
      <div className="text-[11px] uppercase tracking-wider text-gray-400 font-semibold mb-2">
        Open positions
      </div>
      {!hasWallet ? (
        <div className="text-xs text-gray-500 italic">Connect wallet to see your open writes.</div>
      ) : isLoading ? (
        <div className="text-xs text-gray-500">Loading…</div>
      ) : shorts.length === 0 ? (
        <div className="text-xs text-gray-500 italic">No open writes.</div>
      ) : (
        <ul className="flex flex-col gap-1.5">{shorts.map(renderRow)}</ul>
      )}
    </>
  );

  if (bare) return <>{body}</>;

  return (
    <div className="rounded-xl border border-gray-800 bg-black/60 px-4 py-3 w-[18rem] text-left">
      {body}
    </div>
  );
}
