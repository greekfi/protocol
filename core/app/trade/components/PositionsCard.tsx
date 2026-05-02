"use client";

import { formatUnits } from "viem";
import { Hint } from "../../components/Hint";
import { useTokenMap } from "../../mint/hooks/useTokenMap";
import { type HeldOption, useAllHeldOptions } from "../hooks/useAllHeldOptions";

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
  /** Render without the outer rounded-card chrome — used when PositionsCard
   *  is nested inside another card (e.g. as a column of the trade action
   *  card). Default: standalone with chrome. */
  bare?: boolean;
  /** When provided, each row becomes clickable and emits the position back
   *  to the parent — same selection flow as clicking Sell/Buy on the
   *  options grid. */
  onSelect?: (h: HeldOption) => void;
  /** Optional separate handler for the per-row "Exercise" link. When present,
   *  rows that hold a long balance render a small Exercise affordance that
   *  jumps into the trade panel with the exercise box opened. */
  onExercise?: (h: HeldOption) => void;
}

export function PositionsCard({ bare = false, onSelect, onExercise }: PositionsCardProps = {}) {
  const { held, isLoading, hasWallet } = useAllHeldOptions();
  const { tokensByAddress } = useTokenMap();

  const tokenFor = (addr: string) => tokensByAddress[addr.toLowerCase()];

  const renderRow = (h: HeldOption) => {
    const underlyingAddr = h.isPut ? h.consideration : h.collateral;
    const underlying = tokenFor(underlyingAddr);
    const symbol = underlying?.symbol ?? `${underlyingAddr.slice(0, 6)}…`;
    // Option/Receipt ERC20s mirror the collateral's decimals.
    const decimals = tokenFor(h.collateral)?.decimals ?? 18;
    // Combined long-short balance display: long-only positive, short-only
    // negative, both renders as "+X, -Y".
    const balanceText =
      h.optionBalance > 0n && h.receiptBalance > 0n
        ? `+${formatAmount(h.optionBalance, decimals)}, -${formatAmount(h.receiptBalance, decimals)}`
        : h.optionBalance > 0n
          ? formatAmount(h.optionBalance, decimals)
          : h.receiptBalance > 0n
            ? `-${formatAmount(h.receiptBalance, decimals)}`
            : "0";

    // Line 2 codes: e.g. "May 9 · C · E" (Call/Put · European/American).
    const styleCode = h.isEuro ? "E" : "A";
    const sideCode = h.isPut ? "P" : "C";

    const inner = (
      <>
        <div className="flex items-baseline justify-between gap-2 tabular-nums">
          <span className="truncate text-gray-100">
            {symbol} {formatStrike(h.strike, h.isPut)}
          </span>
          <span className="text-gray-300 shrink-0">{balanceText}</span>
        </div>
        <div className="text-gray-500 text-[11px] tabular-nums">
          {formatExpiry(h.expiration)} · {sideCode} · {styleCode}
        </div>
      </>
    );

    const boxBase =
      "block rounded-md border border-gray-800/80 bg-black/30 px-2 py-1.5";

    if (!onSelect) {
      return (
        <li key={h.option} className={boxBase}>
          {inner}
        </li>
      );
    }

    return (
      <li key={h.option} className={`${boxBase} hover:border-gray-700 hover:bg-blue-500/5 transition-colors`}>
        <button
          type="button"
          onClick={() => onSelect(h)}
          className="w-full text-left"
        >
          {inner}
        </button>
        {onExercise && h.optionBalance > 0n && (
          <Hint tip="Open the exercise panel for this option." underline={false}>
            <button
              type="button"
              onClick={() => onExercise(h)}
              className="block mt-0.5 text-[11px] text-gray-400 underline underline-offset-2 hover:text-blue-200"
            >
              exercise
            </button>
          </Hint>
        )}
      </li>
    );
  };

  const body = (
    <>
      <div className="text-[11px] uppercase tracking-wider text-gray-400 font-semibold mb-2">Positions</div>
      {!hasWallet ? (
        <div className="text-xs text-gray-500 italic">Connect wallet to see your option positions.</div>
      ) : isLoading ? (
        <div className="text-xs text-gray-500">Loading…</div>
      ) : held.length === 0 ? (
        <div className="text-xs text-gray-500 italic">No option positions.</div>
      ) : (
        <ul className="space-y-1.5 text-xs">{held.map(renderRow)}</ul>
      )}
    </>
  );

  if (bare) return body;

  return (
    <div className="rounded-xl border border-gray-800 bg-black/60 px-4 py-3 min-w-[14rem] max-w-xs flex-1 text-left">
      {body}
    </div>
  );
}
