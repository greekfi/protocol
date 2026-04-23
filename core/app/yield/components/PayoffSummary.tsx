import Image from "next/image";
import { useState } from "react";
import { formatUnits } from "viem";
import type { TradableOption } from "../../trade/hooks/useTradableOptions";

function displayStrike(opt: TradableOption): number {
  const raw = opt.isPut && opt.strike > 0n ? 10n ** 36n / opt.strike : opt.strike;
  return Number(formatUnits(raw, 18));
}

function formatMoney(n: number): string {
  if (!Number.isFinite(n)) return "—";
  if (n >= 1000) return n.toLocaleString(undefined, { maximumFractionDigits: 0 });
  if (n >= 1) return n.toLocaleString(undefined, { maximumFractionDigits: 2 });
  return n.toPrecision(2);
}

function formatQty(n: number): string {
  if (!Number.isFinite(n) || n === 0) return "—";
  if (n >= 100) return n.toLocaleString(undefined, { maximumFractionDigits: 0 });
  if (n >= 1) return n.toLocaleString(undefined, { maximumFractionDigits: 2 });
  return n.toPrecision(2);
}

function TokenLogo({ symbol, size = 18 }: { symbol: string; size?: number }) {
  const [errored, setErrored] = useState(false);
  if (errored) {
    return (
      <span
        className="inline-flex items-center justify-center rounded-full bg-gray-700 text-[10px] font-semibold text-white"
        style={{ width: size, height: size }}
      >
        {symbol[0]}
      </span>
    );
  }
  return (
    <Image
      src={`/tokens/${symbol.toLowerCase()}.png`}
      alt={symbol}
      width={size}
      height={size}
      className="rounded-full inline-block align-middle"
      onError={() => setErrored(true)}
    />
  );
}

interface PayoffSummaryProps {
  option: TradableOption | null;
  underlyingSymbol: string;
  stableSymbol: string;
  mode: "calls" | "puts";
  amount?: number;
}

export function PayoffSummary({
  option,
  underlyingSymbol,
  stableSymbol,
  mode,
  amount = 0,
}: PayoffSummaryProps) {
  if (!option) {
    return (
      <div className="text-sm text-gray-500">
        Pick a strike/expiry in the grid below to see the payoff.
      </div>
    );
  }
  const strike = displayStrike(option);
  const strikeLabel = `$${formatMoney(strike)}`;
  const qty = amount > 0 ? amount : 1;

  const secondsToExpiry = Number(option.expiration) - Math.floor(Date.now() / 1000);
  const daysToExpiry = Math.max(0, Math.round(secondsToExpiry / 86400));
  const daysLabel = daysToExpiry === 1 ? "In 1 day" : `In ${daysToExpiry} days`;

  // For calls: writer deposits `qty` of underlying; if called away receives strike*qty of stable.
  // For puts : writer deposits `qty` USDC-notional; if exercised receives qty/strike of underlying.
  const stableTotal = strike * qty;
  const underlyingTotal = mode === "calls" ? qty : qty / strike;
  const stableQtyLabel = `${formatMoney(stableTotal)}`;
  const underlyingQtyLabel = `${formatQty(underlyingTotal)}`;

  const stableLine = (
    <div className="flex items-center gap-2 flex-wrap">
      <span className="text-gray-500">
        if <span className="text-blue-200">{underlyingSymbol}</span> &gt; {strikeLabel}, receive
      </span>
      <span className="text-emerald-300 tabular-nums font-medium">
        ${stableQtyLabel} {stableSymbol}
      </span>
      <TokenLogo symbol={stableSymbol} />
    </div>
  );

  const underlyingLine = (
    <div className="flex items-center gap-2 flex-wrap">
      <span className="text-gray-500">
        if <span className="text-blue-200">{underlyingSymbol}</span> &lt; {strikeLabel}, receive
      </span>
      <span className="text-emerald-300 tabular-nums font-medium">
        {underlyingQtyLabel} {underlyingSymbol}
      </span>
      <TokenLogo symbol={underlyingSymbol} />
    </div>
  );

  return (
    <div className="text-sm leading-relaxed flex flex-col gap-2">
      <div className="text-sm font-semibold text-blue-200 tabular-nums">{daysLabel}</div>
      <div className="flex flex-col gap-3 pl-4">
        {mode === "calls" ? (
          <>
            {stableLine}
            {underlyingLine}
          </>
        ) : (
          <>
            {underlyingLine}
            {stableLine}
          </>
        )}
      </div>
    </div>
  );
}
