"use client";

import { formatUnits } from "viem";
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

interface HoldingsCardProps {
  /** Render without the outer rounded-card chrome — used when HoldingsCard
   *  is nested inside another card (e.g. as the footer of the balances
   *  ApprovalsCard on /trade). Default: standalone with chrome. */
  bare?: boolean;
}

export function HoldingsCard({ bare = false }: HoldingsCardProps = {}) {
  const { held, isLoading, hasWallet } = useAllHeldOptions();
  const { allTokensMap } = useTokenMap();

  const tokenFor = (addr: string) => {
    const lc = addr.toLowerCase();
    return Object.values(allTokensMap).find(t => t.address.toLowerCase() === lc);
  };

  const renderRow = (h: HeldOption) => {
    const underlyingAddr = h.isPut ? h.consideration : h.collateral;
    const underlying = tokenFor(underlyingAddr);
    const symbol = underlying?.symbol ?? `${underlyingAddr.slice(0, 6)}…`;
    // Option/Receipt ERC20s mirror the collateral's decimals.
    const decimals = tokenFor(h.collateral)?.decimals ?? 18;
    return (
      <li key={h.option} className="flex items-baseline justify-between gap-3 tabular-nums">
        <span className="truncate text-gray-300">
          {symbol} {formatStrike(h.strike, h.isPut)} {h.isPut ? "P" : "C"} ·{" "}
          <span className="text-gray-500">{formatExpiry(h.expiration)}</span>
        </span>
        <span className="flex items-baseline gap-2 shrink-0">
          {h.optionBalance > 0n && (
            <span className="text-blue-300">L {formatAmount(h.optionBalance, decimals)}</span>
          )}
          {h.receiptBalance > 0n && (
            <span className="text-orange-300">S {formatAmount(h.receiptBalance, decimals)}</span>
          )}
        </span>
      </li>
    );
  };

  const body = (
    <>
      <div className="text-[11px] uppercase tracking-wider text-gray-400 font-semibold mb-2">Holdings</div>
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
