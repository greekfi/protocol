import { useEffect } from "react";
import { formatUnits } from "viem";
import { useChainId, useReadContract } from "wagmi";
import { useBebopQuote } from "../../trade/hooks/useBebopQuote";
import { useBebopTrade } from "../../trade/hooks/useBebopTrade";
import type { TradableOption } from "../../trade/hooks/useTradableOptions";
import type { SellApprovals } from "../hooks/useSellApprovals";
import { PayoffSummary } from "./PayoffSummary";

const ERC20_ABI = [
  {
    name: "decimals",
    type: "function",
    stateMutability: "view",
    inputs: [],
    outputs: [{ type: "uint8" }],
  },
] as const;

const USDC: Record<number, string> = {
  1: "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48",
  8453: "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913",
  42161: "0xaf88d065e77c8cC2239327C5EDb3A432268e5831",
};

function displayStrike(opt: TradableOption): number {
  const raw = opt.isPut && opt.strike > 0n ? 10n ** 36n / opt.strike : opt.strike;
  return Number(formatUnits(raw, 18));
}

function formatMoney(n: number | undefined): string {
  if (n === undefined || !Number.isFinite(n)) return "—";
  if (n >= 1) return n.toLocaleString(undefined, { maximumFractionDigits: 2 });
  if (n >= 0.01) return n.toFixed(3);
  return n.toPrecision(2);
}

function formatExpiry(expiration: bigint): string {
  const d = new Date(Number(expiration) * 1000);
  return d.toLocaleDateString(undefined, { month: "short", day: "numeric", year: "numeric", timeZone: "UTC" });
}

interface SellPanelProps {
  option: TradableOption | null;
  depositSymbol: string;
  underlyingSymbol: string;
  stableSymbol: string;
  mode: "calls" | "puts";
  amount: string;
  onAmountChange: (v: string) => void;
  approvals: SellApprovals;
}

export function SellPanel({
  option,
  depositSymbol,
  underlyingSymbol,
  stableSymbol,
  mode,
  amount,
  onAmountChange,
  approvals,
}: SellPanelProps) {
  const chainId = useChainId();
  const paymentToken = USDC[chainId] ?? USDC[1];
  const optionToken = option?.optionAddress;

  const { data: usdcDecimalsData } = useReadContract({
    address: paymentToken as `0x${string}`,
    abi: ERC20_ABI,
    functionName: "decimals",
  });
  const usdcDecimals = usdcDecimalsData ?? 6;

  const sellAmountStr = approvals.sellAmount > 0n ? approvals.sellAmount.toString() : undefined;

  const { data: quote, isLoading: quoteLoading } = useBebopQuote({
    buyToken: paymentToken,
    sellToken: optionToken ?? "",
    sellAmount: sellAmountStr,
    enabled: !!option && !!sellAmountStr,
  });

  const { executeTrade, status, error: tradeError, txHash, reset } = useBebopTrade();
  useEffect(() => {
    reset();
  }, [option, reset]);

  const handleSell = async () => {
    if (!quote) {
      console.warn("[yield] Deposit clicked with no quote", { option: option?.optionAddress });
      return;
    }
    console.log("[yield] executing trade", {
      source: quote.source,
      buyAmount: quote.buyAmount,
      sellAmount: quote.sellAmount,
      approvalsSatisfied: approvals.allSatisfied,
    });
    try {
      await executeTrade(quote);
    } catch (e) {
      console.error("[yield] sell failed", e);
    }
  };

  const proceeds = quote?.buyAmount ? Number(formatUnits(BigInt(quote.buyAmount), usdcDecimals)) : undefined;
  const pricePerOption = proceeds && parseFloat(amount) > 0 ? proceeds / parseFloat(amount) : undefined;
  const isSelling = status === "preparing" || status === "pending";

  // Human-readable reason the Deposit button is disabled, for the tooltip.
  const disabledReason = !option
    ? "Pick a strike/expiry above"
    : !approvals.allSatisfied
      ? "Finish the approvals in the card on the right"
      : !quote
        ? quoteLoading
          ? "Fetching quote…"
          : "No quote available yet — is the market maker running?"
        : isSelling
          ? "Waiting for on-chain confirmation"
          : undefined;

  const strikeLabel = option ? `$${formatMoney(displayStrike(option))}` : "—";
  const expiryLabel = option ? formatExpiry(option.expiration) : "—";

  return (
    <div className="mt-3 pt-3 border-t border-[#2F50FF]/25">
      <div className="mb-2 text-base font-semibold text-blue-200 tabular-nums">
        {strikeLabel} · {expiryLabel}
      </div>

      <div className="mb-3">
        <PayoffSummary
          option={option}
          underlyingSymbol={underlyingSymbol}
          stableSymbol={stableSymbol}
          mode={mode}
          amount={parseFloat(amount) || 0}
        />
      </div>

      <div className="flex flex-wrap gap-3 items-stretch">
        <div className="flex items-center rounded-lg border border-gray-800 bg-black/50 focus-within:border-[#2F50FF] w-44">
          <input
            type="text"
            inputMode="decimal"
            maxLength={8}
            value={amount}
            onChange={e => {
              const v = e.target.value;
              if (/^\d*\.?\d*$/.test(v) && v.length <= 8) onAmountChange(v);
            }}
            disabled={!option}
            placeholder="0"
            className="w-full px-3 py-2 bg-transparent text-blue-100 text-base outline-none disabled:opacity-50 tabular-nums"
          />
          <span className="pr-3 text-xs text-gray-500 uppercase tracking-wider">{depositSymbol}</span>
        </div>

        <button
          type="button"
          onClick={handleSell}
          disabled={!option || !quote || isSelling || !approvals.allSatisfied}
          className="px-3 py-1.5 rounded-lg bg-[#2F50FF] hover:bg-[#35F3FF] hover:text-[#0a0a0a] text-white text-sm font-semibold disabled:opacity-50 transition-colors"
          title={disabledReason}
        >
          {isSelling ? "Depositing…" : status === "success" ? "Deposited ✓" : "Deposit"}
        </button>
      </div>

      <div className="mt-3 flex flex-wrap items-center gap-x-5 gap-y-1 text-sm">
        <span className="text-gray-500">
          Receive{" "}
          <span className="text-emerald-300 font-medium tabular-nums">
            {quoteLoading ? "…" : `$${formatMoney(proceeds)}`}
          </span>
        </span>
        <span className="text-gray-500">
          Per option{" "}
          <span className="text-blue-200 tabular-nums">${formatMoney(pricePerOption)}</span>
        </span>
      </div>

      {tradeError && <div className="mt-2 text-xs text-red-400">{tradeError}</div>}
      {txHash && <div className="mt-2 text-xs text-gray-400 font-mono break-all">tx {txHash}</div>}
    </div>
  );
}
