import { useEffect, useState } from "react";
import { formatUnits, parseUnits } from "viem";
import { useChainId, useReadContract } from "wagmi";
import { Hint } from "../../components/Hint";
import { useBebopQuote } from "../../trade/hooks/useBebopQuote";
import { useBebopTrade } from "../../trade/hooks/useBebopTrade";
import type { TradableOption } from "../../trade/hooks/useTradableOptions";
import type { SellApprovals } from "../hooks/useSellApprovals";
import { PayoffSummary } from "./PayoffSummary";
import { usdcFor } from "../../data/chains";

const ERC20_ABI = [
  {
    name: "decimals",
    type: "function",
    stateMutability: "view",
    inputs: [],
    outputs: [{ type: "uint8" }],
  },
] as const;

function formatMoney(n: number | undefined): string {
  if (n === undefined || !Number.isFinite(n)) return "—";
  if (n >= 1) return n.toLocaleString(undefined, { maximumFractionDigits: 2 });
  if (n >= 0.01) return n.toFixed(3);
  return n.toPrecision(2);
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
  /** Hide the strike·expiry header (when the parent already renders one). */
  hideDescriptor?: boolean;
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
  const paymentToken = usdcFor(chainId) ?? usdcFor(1)!;
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
    if (!quote) return;
    try {
      await executeTrade(quote);
    } catch (e) {
      console.error("[yield] sell failed", e);
    }
  };

  const proceeds = quote?.buyAmount ? Number(formatUnits(BigInt(quote.buyAmount), usdcDecimals)) : undefined;
  const amountFloat = parseFloat(amount);
  const pricePerOption =
    proceeds !== undefined && Number.isFinite(amountFloat) && amountFloat > 0
      ? proceeds / amountFloat
      : undefined;
  const isSelling = status === "preparing" || status === "pending";

  // USDC input bidirectionally linked to the deposit amount via the live
  // per-option price. Activeinput tracks which side the user is typing in.
  const [usdcInput, setUsdcInput] = useState<string>("");
  const [activeInput, setActiveInput] = useState<"deposit" | "usdc">("deposit");
  useEffect(() => {
    if (activeInput === "deposit" && proceeds !== undefined) {
      setUsdcInput(proceeds.toFixed(2));
    }
  }, [activeInput, proceeds]);

  const [showExplain, setShowExplain] = useState(false);

  const disabledReason = !option
    ? "Pick a strike/expiry below"
    : !approvals.allSatisfied
      ? "Finish the approvals on the right"
      : !quote
        ? quoteLoading
          ? "Fetching quote…"
          : "No quote available yet — is the market maker running?"
        : isSelling
          ? "Waiting for on-chain confirmation"
          : undefined;

  return (
    <div>
      <div className="mb-2 text-sm text-gray-500">
        <span className="text-white tabular-nums">${formatMoney(pricePerOption)}</span> per option
      </div>

      <div className="flex gap-2 items-stretch">
        <div className="flex flex-col gap-1.5 flex-1 min-w-0">
          <div className="flex items-center border border-gray-800 bg-black/50 focus-within:border-[#2F50FF]">
            <input
              type="text"
              inputMode="decimal"
              maxLength={12}
              value={amount}
              disabled={!option}
              onFocus={() => setActiveInput("deposit")}
              onChange={e => {
                const v = e.target.value;
                if (!/^\d*\.?\d*$/.test(v) || v.length > 12) return;
                setActiveInput("deposit");
                onAmountChange(v);
              }}
              placeholder="0"
              className="w-full px-2 py-1 bg-transparent text-white text-sm outline-none disabled:opacity-50 tabular-nums"
            />
            <span className="px-1 text-[10px] text-gray-500 uppercase tracking-wider">{depositSymbol}</span>
            <span className="pr-2 text-gray-500 text-sm" aria-hidden>↑</span>
          </div>
          <div className="flex items-center border border-gray-800 bg-black/50 focus-within:border-[#2F50FF]">
            <input
              type="text"
              inputMode="decimal"
              maxLength={14}
              value={usdcInput}
              disabled={!option}
              onFocus={() => setActiveInput("usdc")}
              onChange={e => {
                const v = e.target.value;
                if (!/^\d*\.?\d*$/.test(v) || v.length > 14) return;
                setActiveInput("usdc");
                setUsdcInput(v);
                const usdcN = parseFloat(v);
                if (pricePerOption !== undefined && pricePerOption > 0 && Number.isFinite(usdcN)) {
                  if (usdcN > 0) {
                    const opts = usdcN / pricePerOption;
                    onAmountChange(opts >= 1 ? opts.toFixed(4) : opts.toPrecision(4));
                  } else {
                    onAmountChange("");
                  }
                }
              }}
              placeholder="0"
              className="w-full px-2 py-1 bg-transparent text-white text-sm outline-none disabled:opacity-50 tabular-nums"
            />
            <span className="px-1 text-[10px] text-gray-500 uppercase tracking-wider">USDC</span>
            <span className="pr-2 text-gray-500 text-sm" aria-hidden>↓</span>
          </div>
        </div>

        {(() => {
          const btn = (
            <button
              type="button"
              onClick={handleSell}
              disabled={!option || !quote || isSelling || !approvals.allSatisfied}
              className="self-stretch px-3 bg-[#2F50FF] hover:bg-[#35F3FF] hover:text-black text-white text-sm font-semibold leading-none disabled:opacity-50 transition-colors"
            >
              {isSelling ? "Depositing…" : status === "success" ? "Deposited ✓" : "Deposit"}
            </button>
          );
          return disabledReason ? (
            <Hint tip={disabledReason} above underline={false}>
              {btn}
            </Hint>
          ) : (
            btn
          );
        })()}
      </div>

      <div className="mt-2 flex items-center gap-2">
        <button
          type="button"
          onClick={() => setShowExplain(s => !s)}
          className="text-xs text-gray-400 hover:text-white underline underline-offset-2"
        >
          {showExplain ? "hide explain" : "explain"}
        </button>
      </div>

      {showExplain && (
        <div className="mt-3 pt-3 border-t border-gray-700/40">
          <PayoffSummary
            option={option}
            underlyingSymbol={underlyingSymbol}
            stableSymbol={stableSymbol}
            mode={mode}
            amount={parseFloat(amount) || 0}
          />
        </div>
      )}

      {tradeError && <div className="mt-2 text-xs text-gray-400">{tradeError}</div>}
      {txHash && <div className="mt-2 text-xs text-gray-400 font-mono break-all">tx {txHash}</div>}
    </div>
  );
}
