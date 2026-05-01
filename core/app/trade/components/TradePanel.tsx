"use client";

import { useEffect, useState } from "react";
import { formatUnits, parseUnits } from "viem";
import { useAccount, useChainId } from "wagmi";
import { useReadOptionBalancesOf, useReadOptionIsEuro } from "~~/generated";
import { ApprovalsCard, type BalanceRow } from "../../components/options/ApprovalsCard";
import { Hint } from "../../components/Hint";
import { useTokenSpot } from "../../lib/useTokenSpot";
import { ExercisePanel } from "./ExercisePanel";
import { useTokenMap } from "../../mint/hooks/useTokenMap";
import { useBebopQuote } from "../hooks/useBebopQuote";
import { useBebopTrade } from "../hooks/useBebopTrade";
import type { TradableOption } from "../hooks/useTradableOptions";
import { type TradeDirection, useTradeApprovals } from "../hooks/useTradeApprovals";
import { usdcFor } from "../../data/chains";

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
  /** Counter bumped by callers (e.g. HoldingsCard's Exercise link) to
   *  request the exercise box be opened. */
  openExerciseSignal?: number;
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

export function TradePanel({
  selectedOption,
  onClose,
  tokenSelector,
  holdings,
  openExerciseSignal,
}: TradePanelProps) {
  const chainId = useChainId();
  const { allTokensMap } = useTokenMap();
  const { address: userAddress } = useAccount();

  // Pull all four balances Option exposes in one call: collateral / consideration / long / short.
  const { data: optionBalances } = useReadOptionBalancesOf({
    address: selectedOption.optionAddress as `0x${string}`,
    args: userAddress ? [userAddress] : undefined,
    query: { enabled: !!userAddress },
  });
  const { data: isEuro } = useReadOptionIsEuro({
    address: selectedOption.optionAddress as `0x${string}`,
  });

  const [direction, setDirection] = useState<TradeDirection>(selectedOption.isBuy ? "buy" : "sell");
  const [amount, setAmount] = useState<string>("1");
  // The two inputs are linked; activeInput tracks which side the user typed
  // last so we don't overwrite their cursor. The option amount is the source
  // of truth for the quote — USDC is just a derived view (or the inverse,
  // depending on which side is active).
  const [usdcInput, setUsdcInput] = useState<string>("");
  const [activeInput, setActiveInput] = useState<"option" | "usdc">("option");

  // Sync direction with the selection coming from OptionsGrid (Buy/Sell button).
  useEffect(() => {
    setDirection(selectedOption.isBuy ? "buy" : "sell");
  }, [selectedOption.isBuy, selectedOption.optionAddress]);

  const [showExercise, setShowExercise] = useState(false);
  // Collapse exercise when the user picks a different option.
  useEffect(() => setShowExercise(false), [selectedOption.optionAddress]);
  // Open exercise when the parent bumps the signal (e.g. HoldingsCard click).
  useEffect(() => {
    if (openExerciseSignal !== undefined && openExerciseSignal > 0) setShowExercise(true);
  }, [openExerciseSignal]);

  const optionToken = selectedOption.optionAddress;
  const paymentToken = usdcFor(chainId) ?? usdcFor(1)!;

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

  // Keep the USDC input mirrored to the quote when the user is driving the
  // option side. When the user is typing in the USDC input, leave their
  // text alone — we already updated `amount` to keep the quote in sync.
  useEffect(() => {
    if (activeInput === "option" && usdcDisplay !== undefined) {
      setUsdcInput(usdcDisplay.toFixed(2));
    }
  }, [activeInput, usdcDisplay]);

  const usdcCostWei = quote?.sellAmount ? BigInt(quote.sellAmount) : undefined;
  const hasEnoughUsdc =
    direction === "buy" &&
    usdcCostWei !== undefined &&
    approvals.usdcBalance !== undefined &&
    approvals.usdcBalance >= usdcCostWei;

  const sellAmountWei = approvals.optionAmountWei;
  const hasEnoughOption =
    direction === "sell" &&
    optionBalances !== undefined &&
    sellAmountWei > 0n &&
    optionBalances.option >= sellAmountWei;
  const insufficientMessage =
    direction === "buy"
      ? !hasEnoughUsdc && usdcCostWei !== undefined && usdcCostWei > 0n
        ? "Not enough USDC"
        : null
      : !hasEnoughOption && sellAmountWei > 0n
        ? "Not enough OPT"
        : null;

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
  // Underlying = collateral on calls, consideration on puts.
  const underlyingSymbol = selectedOption.isPut ? consSymbol : collSymbol;
  const spotPrice = useTokenSpot(underlyingSymbol);

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
  const collateralErc20Done = (approvals.collateralErc20Allowance ?? 0n) > 0n;
  const collateralFactoryDone = (approvals.collateralFactoryAllowance ?? 0n) > 0n;
  const collateralApproved = collateralErc20Done && collateralFactoryDone;
  const collateralHalfApproved = !collateralApproved && (collateralErc20Done || collateralFactoryDone);

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
      partial: collateralHalfApproved,
      pending: approvals.isApproving,
      onAction: approvals.handleApproveCollateral,
      title: `Approve ${collSymbol} for the factory (two layers: ERC20 + factory-internal). Required for auto-mint to pull collateral on sell.`,
    },
    {
      label: "Keeper Settlement",
      done: approvals.keeperApproved === true,
      pending: approvals.isApproving,
      onAction: approvals.handleAllowKeeper,
      title: "Allow Keeper to settle on your behalf during exercise/settlement window.",
    },
  ];

  const strikeLabel = `$${formatMoney(displayStrike(selectedOption.strike, selectedOption.isPut))}`;
  const expiryLabel = formatExpiry(selectedOption.expiration);

  return (
    <div className="w-full flex flex-wrap gap-3 items-stretch justify-center">
      {/* Action card */}
      <div className="rounded-xl border border-[#2F50FF]/40 bg-gradient-to-b from-[#2F50FF]/10 to-black/60 shadow-lg px-4 py-3 w-[20rem]">
        <div className="mb-3 flex items-center gap-3 flex-wrap">
          <div className="text-base font-semibold text-white tabular-nums">
            {strikeLabel} · {expiryLabel} ·{" "}
            {isEuro !== undefined && `${isEuro ? "Euro" : "American"} `}
            {selectedOption.isPut ? "Put" : "Call"}
          </div>
          {spotPrice !== undefined && (
            <span className="text-sm text-gray-400">
              spot <span className="text-white tabular-nums">${formatMoney(spotPrice)}</span>
            </span>
          )}
          <div className="ml-auto">{tokenSelector}</div>
        </div>

        <div className="flex flex-col gap-2">
          {/* Row 1: OPT input + Sell|Buy direction toggle */}
          <div className="flex items-center gap-2">
            <div className="flex items-center border border-gray-800 bg-black/50 focus-within:border-[#2F50FF] w-32">
              <input
                type="text"
                inputMode="decimal"
                maxLength={8}
                value={amount}
                onFocus={() => setActiveInput("option")}
                onChange={e => {
                  const v = e.target.value;
                  if (!/^\d*\.?\d*$/.test(v) || v.length > 8) return;
                  setActiveInput("option");
                  setAmount(v);
                }}
                placeholder="0"
                className="w-full px-2 py-1 bg-transparent text-blue-100 text-sm outline-none tabular-nums"
              />
              {(() => {
                // sell → user's long balance; buy → most options affordable
                // with current USDC at the current per-option price.
                let maxN: number | undefined;
                if (direction === "sell" && optionBalances?.option !== undefined) {
                  maxN = Number(formatUnits(optionBalances.option, optionDecimals));
                } else if (
                  direction === "buy" &&
                  approvals.usdcBalance !== undefined &&
                  pricePerOption !== undefined &&
                  pricePerOption > 0
                ) {
                  maxN = Number(formatUnits(approvals.usdcBalance, approvals.usdcDecimals)) / pricePerOption;
                }
                if (!maxN || !Number.isFinite(maxN) || maxN <= 0) return null;
                const maxStr = maxN >= 1 ? maxN.toFixed(4) : maxN.toPrecision(4);
                return (
                  <button
                    type="button"
                    onClick={() => {
                      setActiveInput("option");
                      setAmount(maxStr);
                    }}
                    className="px-1 text-[10px] uppercase tracking-wider text-blue-300 hover:text-blue-200"
                  >
                    max
                  </button>
                );
              })()}
              <span className="pr-2 text-[10px] text-gray-500 uppercase tracking-wider">OPT</span>
            </div>
            <div className="flex rounded-md border border-gray-700 overflow-hidden text-[11px] shrink-0">
              <button
                type="button"
                onClick={() => setDirection("sell")}
                className={`px-1.5 py-0.5 ${direction === "sell" ? "bg-blue-500 text-white" : "bg-black/40 text-gray-300 hover:bg-black/60"}`}
              >
                Sell
              </button>
              <button
                type="button"
                onClick={() => setDirection("buy")}
                className={`px-1.5 py-0.5 ${direction === "buy" ? "bg-blue-500 text-white" : "bg-black/40 text-gray-300 hover:bg-black/60"}`}
              >
                Buy
              </button>
            </div>
          </div>

          {/* Row 2: USDC input + primary action button */}
          <div className="flex items-center gap-2">
            <div className="flex items-center border border-gray-800 bg-black/50 focus-within:border-[#2F50FF] w-32">
              <input
                type="text"
                inputMode="decimal"
                maxLength={12}
                value={usdcInput}
                onFocus={() => setActiveInput("usdc")}
                onChange={e => {
                  const v = e.target.value;
                  if (!/^\d*\.?\d*$/.test(v) || v.length > 12) return;
                  setActiveInput("usdc");
                  setUsdcInput(v);
                  const usdcN = parseFloat(v);
                  if (pricePerOption !== undefined && pricePerOption > 0 && Number.isFinite(usdcN)) {
                    if (usdcN > 0) {
                      const opts = usdcN / pricePerOption;
                      setAmount(opts >= 1 ? opts.toFixed(4) : opts.toPrecision(4));
                    } else {
                      setAmount("");
                    }
                  }
                }}
                placeholder="0"
                className="w-full px-2 py-1 bg-transparent text-blue-100 text-sm outline-none tabular-nums"
              />
              {direction === "buy" && usdcCostWei !== undefined && (
                <span
                  className={`pr-1 text-xs ${hasEnoughUsdc ? "text-emerald-400" : "text-red-400"}`}
                  title={hasEnoughUsdc ? "USDC balance covers cost" : "Insufficient USDC balance"}
                >
                  {hasEnoughUsdc ? "✓" : "✗"}
                </span>
              )}
              <span className="pr-2 text-[10px] text-gray-500 uppercase tracking-wider">USDC</span>
            </div>
            <button
              type="button"
              onClick={handleTrade}
              disabled={!quote || isTrading || !approvals.allSatisfied}
              className="shrink-0 h-7 px-3 rounded-lg text-white text-base leading-none font-semibold disabled:opacity-50 transition-colors bg-blue-500 hover:bg-blue-400"
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
        </div>

        <div className="mt-3 flex flex-wrap items-center gap-x-5 gap-y-1 text-sm">
          <span className="text-gray-500">
            Per option <span className="text-white tabular-nums">${formatMoney(pricePerOption)}</span>
          </span>
          {insufficientMessage && (
            <span className="text-xs text-amber-300/90 ml-auto">{insufficientMessage}</span>
          )}
        </div>

        {tradeError && <div className="mt-2 text-xs text-red-400">{tradeError}</div>}
        {txHash && <div className="mt-2 text-xs text-gray-400 font-mono break-all">tx {txHash}</div>}
      </div>

      {/* Single combined column. Top: balances as a 2×2 grid. Bottom:
          Holdings on the left, the Approvals list on the right, on one
          row. Drops the second card entirely so the panel reads
          left-to-right (action → balances + holdings/approvals). */}
      <div className="w-[22rem] max-w-full">
        <ApprovalsCard
          steps={[]}
          balances={balances}
          balancesLayout="grid"
          footer={
            <div className="space-y-3">
              <div>{holdings}</div>
              <div className="pt-3 border-t border-gray-700/40">
                <div className="text-[11px] uppercase tracking-wider text-gray-400 font-semibold mb-2">
                  <Hint
                    width="w-72"
                    tip={[
                      <span key="usdc">
                        <b className="text-gray-100">USDC</b> — needed to buy options.
                      </span>,
                      <span key="opt">
                        <b className="text-gray-100">Option</b> — needed to sell options you already hold.
                      </span>,
                      <span key="auto">
                        <b className="text-gray-100">Auto-mint + {collSymbol}</b> — needed to write covered calls atomically (sell options against collateral in a single tx, no manual mint step).
                      </span>,
                      <span key="keeper">
                        <b className="text-gray-100">Keeper Settlement</b> — allow Keeper to settle on your behalf during the exercise/settlement window.
                      </span>,
                    ]}
                  >
                    Trading Approvals
                  </Hint>
                </div>
                <ApprovalsList steps={steps} />
              </div>
            </div>
          }
        />
      </div>

      {showExercise && (
        <ExercisePanel
          optionAddress={selectedOption.optionAddress}
          considerationAddress={selectedOption.considerationAddress}
          optionDecimals={optionDecimals}
          consDecimals={consDecimals}
          consSymbol={consSymbol}
          onClose={() => setShowExercise(false)}
        />
      )}
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
    partial?: boolean;
    pending: boolean;
    onAction?: () => void;
    title?: string;
  }>;
}) {
  // [Approve] token   →   [✓] token
  // The leading pill is the action: orange "Approve" while pending, green
  // checkmark once done. Same shape/size in both states so the labels stay
  // at the same x-position across rows. Done pills are non-interactive.
  const PILL_BASE =
    "inline-flex items-center justify-center min-w-[4.25rem] px-2 py-0.5 rounded-md text-xs font-semibold transition-colors shrink-0";
  return (
    <ul className="grid grid-cols-2 gap-x-4 gap-y-2 text-sm">
      {steps.map(step => (
        <li key={step.label} className="flex items-center gap-2 min-w-0">
          {step.done ? (
            <span
              className="inline-flex items-center justify-center min-w-[4.25rem] text-emerald-400 text-base shrink-0"
              aria-hidden
            >
              ✓
            </span>
          ) : (
            <button
              type="button"
              onClick={step.onAction}
              disabled={step.pending || !step.onAction}
              className={`${PILL_BASE} ${
                step.partial
                  ? "bg-pink-500 hover:bg-pink-400"
                  : "bg-[#FF8300] hover:bg-[#e07400]"
              } text-black disabled:opacity-50`}
            >
              {step.pending ? "…" : "Approve"}
            </button>
          )}
          <span className={`truncate ${step.done ? "text-gray-500" : "text-gray-300"}`}>
            {step.title ? <Hint tip={step.title} above>{step.label}</Hint> : step.label}
          </span>
        </li>
      ))}
    </ul>
  );
}
