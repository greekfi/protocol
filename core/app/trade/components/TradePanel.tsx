"use client";

import { useEffect, useState } from "react";
import { formatUnits, parseUnits } from "viem";
import { useAccount, useChainId } from "wagmi";
import { useReadOptionBalancesOf } from "~~/generated";
import { ApprovalsCard, type BalanceRow } from "../../components/options/ApprovalsCard";
import { useTokenMap } from "../../mint/hooks/useTokenMap";
import { useBebopQuote } from "../hooks/useBebopQuote";
import { useBebopTrade } from "../hooks/useBebopTrade";
import type { TradableOption } from "../hooks/useTradableOptions";
import { type TradeDirection, useTradeApprovals } from "../hooks/useTradeApprovals";

const USDC: Record<number, string> = {
  1: "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48",
  8453: "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913",
  42161: "0xaf88d065e77c8cC2239327C5EDb3A432268e5831",
};

interface TradePanelProps {
  selectedOption: {
    optionAddress: string;
    strike: bigint;
    expiration: bigint;
    isPut: boolean;
    collateralAddress: string;
    considerationAddress: string;
    isBuy: boolean;
  };
  onClose: () => void;
  /** Optional element rendered at the top of the swap card — used to "house"
   *  the underlying token selector pill once an option is picked. */
  tokenSelector?: React.ReactNode;
  /** Optional 4th-column slot — rendered alongside Balances + Approvals so
   *  every panel shares the same flex-wrap row. */
  holdings?: React.ReactNode;
}

function displayStrike(strike: bigint, isPut: boolean): number {
  const raw = isPut && strike > 0n ? 10n ** 36n / strike : strike;
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

function formatBalance(raw: bigint | undefined, decimals: number): string {
  if (raw === undefined) return "—";
  const n = Number(formatUnits(raw, decimals));
  if (n === 0) return "0";
  if (n >= 1) return n.toLocaleString(undefined, { maximumFractionDigits: 2 });
  if (n >= 0.0001) return n.toFixed(4);
  return n.toPrecision(2);
}

export function TradePanel({ selectedOption, onClose, tokenSelector, holdings }: TradePanelProps) {
  const chainId = useChainId();
  const { allTokensMap } = useTokenMap();
  const { address: userAddress } = useAccount();

  // Pull all four balances Option exposes in one call: collateral / consideration / long / short.
  const { data: optionBalances } = useReadOptionBalancesOf({
    address: selectedOption.optionAddress as `0x${string}`,
    args: userAddress ? [userAddress] : undefined,
    query: { enabled: !!userAddress },
  });

  const [direction, setDirection] = useState<TradeDirection>(selectedOption.isBuy ? "buy" : "sell");
  const [amount, setAmount] = useState<string>("1");

  // Sync direction with the selection coming from OptionsGrid (Buy/Sell button).
  useEffect(() => {
    setDirection(selectedOption.isBuy ? "buy" : "sell");
  }, [selectedOption.isBuy, selectedOption.optionAddress]);

  const optionToken = selectedOption.optionAddress;
  const paymentToken = USDC[chainId] ?? USDC[1];

  // Option ERC20 decimals mirror collateral decimals (see Option.sol). The
  // Bebop quote needs the *raw* token amount, so we must use this — not the
  // hard-coded 18 — or puts on USDC-collateralised collateral come back with
  // a price ~10^12× off.
  const optionDecimals =
    Object.values(allTokensMap).find(
      t => t.address.toLowerCase() === selectedOption.collateralAddress.toLowerCase(),
    )?.decimals ?? 18;

  // Build the "TradableOption" shape useTradeApprovals needs from the selection.
  const optionForApprovals: TradableOption = {
    optionAddress: selectedOption.optionAddress,
    collateralAddress: selectedOption.collateralAddress,
    considerationAddress: selectedOption.considerationAddress,
    expiration: selectedOption.expiration,
    strike: selectedOption.strike,
    isPut: selectedOption.isPut,
    redemptionAddress: "",
  };

  // Bebop quote — for buys we know the option amount we want; for sells we know the option amount we have.
  const { data: quote, isLoading: quoteLoading } = useBebopQuote(
    direction === "buy"
      ? {
          buyToken: optionToken,
          sellToken: paymentToken,
          buyAmount:
            amount && parseFloat(amount) > 0 ? parseUnits(amount, optionDecimals).toString() : undefined,
          enabled: amount !== "" && parseFloat(amount) > 0,
        }
      : {
          buyToken: paymentToken,
          sellToken: optionToken,
          sellAmount:
            amount && parseFloat(amount) > 0 ? parseUnits(amount, optionDecimals).toString() : undefined,
          enabled: amount !== "" && parseFloat(amount) > 0,
        },
  );

  const approvals = useTradeApprovals({
    option: optionForApprovals,
    amount,
    direction,
    usdcQuoteAmount: direction === "buy" ? quote?.sellAmount : undefined,
  });

  const { executeTrade, status, error: tradeError, txHash, reset } = useBebopTrade();
  useEffect(() => {
    reset();
  }, [optionToken, direction, reset]);

  const handleTrade = async () => {
    if (!quote) return;
    try {
      await executeTrade(quote);
      approvals.refetchAll();
    } catch (e) {
      console.error("[trade] failed", e);
    }
  };

  const isTrading = status === "preparing" || status === "pending";

  // The MM normalises `buyAmount`/`sellAmount` by spot (e.g. for an ETH put
  // they come back as `BS_price / spot` in 1e18 form, NOT raw USDC) — so we
  // can't `formatUnits(..., 6)` them. Use the `price` field instead, which
  // is the per-option USDC price ready to display.
  const pricePerOption = quote?.price ? parseFloat(quote.price) : undefined;
  const amountFloat = parseFloat(amount);
  const usdcDisplay =
    pricePerOption !== undefined && Number.isFinite(amountFloat) && amountFloat > 0
      ? pricePerOption * amountFloat
      : undefined;

  const disabledReason = !approvals.allSatisfied
    ? "Finish the approvals in the card on the right"
    : !quote
      ? quoteLoading
        ? "Fetching quote…"
        : "No quote available — is the market maker running?"
      : isTrading
        ? "Waiting for on-chain confirmation"
        : undefined;

  // ApprovalsCard inputs.
  const usdcSymbol =
    Object.values(allTokensMap).find(t => t.address.toLowerCase() === paymentToken.toLowerCase())?.symbol ?? "USDC";
  const collSymbol =
    Object.values(allTokensMap).find(
      t => t.address.toLowerCase() === selectedOption.collateralAddress.toLowerCase(),
    )?.symbol ?? "Collateral";
  const consSymbol =
    Object.values(allTokensMap).find(
      t => t.address.toLowerCase() === selectedOption.considerationAddress.toLowerCase(),
    )?.symbol ?? "Consideration";

  const collDecimals =
    Object.values(allTokensMap).find(
      t => t.address.toLowerCase() === selectedOption.collateralAddress.toLowerCase(),
    )?.decimals ?? 18;
  const consDecimals =
    Object.values(allTokensMap).find(
      t => t.address.toLowerCase() === selectedOption.considerationAddress.toLowerCase(),
    )?.decimals ?? approvals.usdcDecimals;

  const balances: BalanceRow[] = optionBalances
    ? [
        {
          label: collSymbol,
          value: formatBalance(optionBalances.collateral, collDecimals),
          dim: optionBalances.collateral === 0n,
        },
        {
          label: consSymbol,
          value: formatBalance(optionBalances.consideration, consDecimals),
          dim: optionBalances.consideration === 0n,
        },
        {
          label: "Option",
          value: formatBalance(optionBalances.option, approvals.optionDecimals),
          dim: optionBalances.option === 0n,
        },
        {
          label: "Short",
          value: formatBalance(optionBalances.receipt, approvals.optionDecimals),
          dim: optionBalances.receipt === 0n,
        },
      ]
    : [];

  // Always show both approval rows so the user can see and grant either side at any time —
  // mirrors /yield's behaviour. "done" reflects whether ANY allowance has been granted, since
  // most users approve max-uint. The trade button's enabled state still uses the strict,
  // direction-aware `needs*Approval` flags (via approvals.allSatisfied).
  const usdcApproved = (approvals.usdcAllowance ?? 0n) > 0n;
  const optionApproved = (approvals.optionAllowance ?? 0n) > 0n || approvals.factoryOperatorApproved === true;
  const autoMintApproved = approvals.autoMintEnabled === true;
  const collateralApproved =
    (approvals.collateralErc20Allowance ?? 0n) > 0n && (approvals.collateralFactoryAllowance ?? 0n) > 0n;

  // Labels are token-only — the Approve button next to each row already
  // says "Approve". Tooltips carry the longer "for Bebop / via operator"
  // explanation for users who hover.
  const steps = [
    {
      label: usdcSymbol,
      done: usdcApproved,
      pending: approvals.isApproving,
      onAction: approvals.handleApproveUsdc,
      title: "Lets Bebop pull USDC when buying or buying-back option tokens.",
    },
    {
      label: "Option",
      done: optionApproved,
      pending: approvals.isApproving,
      onAction: approvals.handleApproveOption,
      title: approvals.factoryOperatorApproved
        ? "Covered by your factory-operator approval."
        : "Lets Bebop pull the option token when selling.",
    },
    {
      label: "Auto-mint",
      done: autoMintApproved,
      pending: approvals.isApproving,
      // Use a distinct on-action so the user can flip auto-mint without
      // the row also triggering an ERC20 approve. The Approve button on
      // this row is just a labelled toggle.
      onAction: approvals.handleEnableAutoMint,
      title:
        "Lets the Option contract auto-mint from your collateral when you transfer options you don't yet hold (required for selling without manually minting first).",
    },
    {
      label: collSymbol,
      done: collateralApproved,
      pending: approvals.isApproving,
      onAction: approvals.handleApproveCollateral,
      title: `Approve ${collSymbol} for the factory (two layers: ERC20 + factory-internal). Required for auto-mint to pull collateral on sell.`,
    },
  ];

  const strikeLabel = `$${formatMoney(displayStrike(selectedOption.strike, selectedOption.isPut))}`;
  const expiryLabel = formatExpiry(selectedOption.expiration);

  return (
    <div className="w-full flex flex-wrap gap-3 items-stretch justify-center">
      {/* Action card */}
      <div className="rounded-xl border border-[#2F50FF]/40 bg-gradient-to-b from-[#2F50FF]/10 to-black/60 shadow-lg px-4 py-3 min-w-[18rem] max-w-[22rem] flex-1">
        <div className="mb-3 flex items-center gap-3 flex-wrap">
          {tokenSelector}
          <div className="text-base font-semibold text-white tabular-nums">
            {strikeLabel} · {expiryLabel} · {selectedOption.isPut ? "Put" : "Call"}
          </div>
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
                if (/^\d*\.?\d*$/.test(v) && v.length <= 8) setAmount(v);
              }}
              placeholder="0"
              className="w-full px-3 py-2 bg-transparent text-blue-100 text-base outline-none tabular-nums"
            />
            <span className="pr-3 text-xs text-gray-500 uppercase tracking-wider">option</span>
          </div>

          <button
            type="button"
            onClick={handleTrade}
            disabled={!quote || isTrading || !approvals.allSatisfied}
            className={`px-3 py-1.5 rounded-lg text-white text-sm font-semibold disabled:opacity-50 transition-colors ${
              direction === "buy"
                ? "bg-blue-500 hover:bg-blue-400"
                : "bg-orange-500 hover:bg-orange-400"
            }`}
            title={disabledReason}
          >
            {isTrading
              ? direction === "buy"
                ? "Buying…"
                : "Selling…"
              : status === "success"
                ? direction === "buy"
                  ? "Bought ✓"
                  : "Sold ✓"
                : direction === "buy"
                  ? "Buy"
                  : "Sell"}
          </button>
        </div>

        <div className="mt-3 flex flex-wrap items-center gap-x-5 gap-y-1 text-sm">
          <span className={direction === "buy" ? "text-blue-300" : "text-orange-300"}>
            {direction === "buy" ? "Cost" : "Receive"}{" "}
            <span className="font-medium tabular-nums">
              {quoteLoading ? "…" : `$${formatMoney(usdcDisplay)}`}
            </span>
          </span>
          <span className="text-gray-500">
            Per option <span className="text-white tabular-nums">${formatMoney(pricePerOption)}</span>
          </span>
          {/* Buy/Sell toggle sits flush right next to the per-option price. */}
          <div className="flex rounded-md border border-gray-700 overflow-hidden text-xs ml-auto">
            <button
              type="button"
              onClick={() => setDirection("buy")}
              className={`px-2 py-1 ${direction === "buy" ? "bg-blue-500 text-white" : "bg-black/40 text-blue-300 hover:bg-black/60"}`}
            >
              Buy
            </button>
            <button
              type="button"
              onClick={() => setDirection("sell")}
              className={`px-2 py-1 ${direction === "sell" ? "bg-orange-500 text-white" : "bg-black/40 text-orange-300 hover:bg-black/60"}`}
            >
              Sell
            </button>
          </div>
        </div>

        {tradeError && <div className="mt-2 text-xs text-red-400">{tradeError}</div>}
        {txHash && <div className="mt-2 text-xs text-gray-400 font-mono break-all">tx {txHash}</div>}
      </div>

      {/* Single combined column. Top: balances as a 2×2 grid. Bottom:
          Holdings on the left, the Approvals list on the right, on one
          row. Drops the second card entirely so the panel reads
          left-to-right (action → balances + holdings/approvals). */}
      <div className="min-w-[20rem] flex-1 max-w-[28rem]">
        <ApprovalsCard
          steps={[]}
          balances={balances}
          balancesLayout="grid"
          footer={
            <div className="space-y-3">
              <div>{holdings}</div>
              <div className="pt-3 border-t border-gray-700/40">
                <div className="text-[11px] uppercase tracking-wider text-gray-400 font-semibold mb-2">
                  Approvals
                </div>
                <ApprovalsList steps={steps} />
              </div>
            </div>
          }
        />
      </div>
    </div>
  );
}

/**
 * Inline approvals list extracted so the trade panel can render it inside
 * the combined balances+holdings+approvals card without nesting another
 * full ApprovalsCard (which would re-print the section headers and chrome).
 */
function ApprovalsList({
  steps,
}: {
  steps: Array<{
    label: string;
    done: boolean;
    pending: boolean;
    onAction?: () => void;
    title?: string;
  }>;
}) {
  // Render every approval on a single horizontal row. Each item is a
  // status dot + token label + (when not yet approved) Approve button.
  return (
    <ul className="flex flex-wrap items-center gap-x-4 gap-y-2 text-sm">
      {steps.map(step => (
        <li key={step.label} className="flex items-center gap-2">
          <span
            className={`inline-flex items-center justify-center w-4 h-4 rounded-full text-[10px] font-bold shrink-0 ${
              step.done ? "bg-emerald-500/80 text-black" : "bg-gray-700 text-gray-400 border border-gray-600"
            }`}
            aria-hidden
          >
            {step.done ? "✓" : ""}
          </span>
          <span
            className={step.done ? "text-gray-500" : "text-gray-300"}
            title={step.title}
          >
            {step.label}
          </span>
          {!step.done && step.onAction && (
            <button
              type="button"
              onClick={step.onAction}
              disabled={step.pending}
              className="px-2 py-0.5 rounded-md bg-[#FF8300] hover:bg-[#e07400] text-black text-xs font-semibold disabled:opacity-50 transition-colors shrink-0"
            >
              {step.pending ? "…" : "Approve"}
            </button>
          )}
        </li>
      ))}
    </ul>
  );
}
