"use client";

import { useEffect, useState } from "react";
import { formatUnits, parseUnits } from "viem";
import { useAccount, useChainId } from "wagmi";
import { useReadOptionBalancesOf, useReadOptionIsEuro } from "~~/generated";
import { type BalanceRow } from "../../components/options/ApprovalsCard";
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
  const { tokensByAddress } = useTokenMap();
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
  const [showApprovalsModal, setShowApprovalsModal] = useState(false);
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
  const collateralToken = tokensByAddress[selectedOption.collateralAddress.toLowerCase()];
  const considerationToken = tokensByAddress[selectedOption.considerationAddress.toLowerCase()];
  const paymentTokenInfo = tokensByAddress[(usdcFor(chainId) ?? usdcFor(1)!).toLowerCase()];
  const optionDecimals = collateralToken?.decimals ?? 18;

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
    // Approvals not done? Route to the walkthrough modal instead of blocking.
    if (!approvals.allSatisfied) {
      setShowApprovalsModal(true);
      return;
    }
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

  const disabledReason = !quote
    ? quoteLoading
      ? "Fetching quote…"
      : "No quote available — is the market maker running?"
    : isTrading
      ? "Waiting for on-chain confirmation"
      : !approvals.allSatisfied
        ? `Approvals needed — click ${direction === "buy" ? "Buy" : "Sell"} to walk through them`
        : insufficientMessage ?? undefined;

  // ApprovalsCard inputs.
  const usdcSymbol = paymentTokenInfo?.symbol ?? "USDC";
  const collSymbol = collateralToken?.symbol ?? "Collateral";
  const consSymbol = considerationToken?.symbol ?? "Consideration";

  const collDecimals = collateralToken?.decimals ?? 18;
  // Underlying = collateral on calls, consideration on puts.
  const underlyingSymbol = selectedOption.isPut ? consSymbol : collSymbol;
  const spotPrice = useTokenSpot(underlyingSymbol);

  const consDecimals = considerationToken?.decimals ?? approvals.usdcDecimals;

  // OPT row collapses long + short into one number. Long-only renders as a
  // positive amount, short-only as negative. If the user holds both sides the
  // row shows them side-by-side with explicit signs, e.g. "+1, -0.3".
  const optValue = optionBalances
    ? optionBalances.option > 0n && optionBalances.receipt > 0n
      ? `+${formatBalance(optionBalances.option, approvals.optionDecimals)}, -${formatBalance(optionBalances.receipt, approvals.optionDecimals)}`
      : optionBalances.option > 0n
        ? formatBalance(optionBalances.option, approvals.optionDecimals)
        : optionBalances.receipt > 0n
          ? `-${formatBalance(optionBalances.receipt, approvals.optionDecimals)}`
          : "0"
    : "—";
  const balances: BalanceRow[] = optionBalances
    ? [
        {
          label: "OPT",
          value: optValue,
          dim: optionBalances.option === 0n && optionBalances.receipt === 0n,
        },
        {
          label: consSymbol,
          value: formatBalance(optionBalances.consideration, consDecimals),
          dim: optionBalances.consideration === 0n,
        },
        {
          label: collSymbol,
          value: formatBalance(optionBalances.collateral, collDecimals),
          dim: optionBalances.collateral === 0n,
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
      <div className="rounded-xl border border-[#2F50FF]/40 bg-gradient-to-b from-[#2F50FF]/10 to-black/60 shadow-lg px-4 py-3 w-[28rem] flex gap-4">
        {/* Left side: descriptor + inputs + price + warnings */}
        <div className="flex-1 min-w-0 flex flex-col">
        <div className="mb-3 text-base font-semibold text-white tabular-nums leading-tight">
          <div>
            {strikeLabel} · {expiryLabel}
          </div>
          <div>
            {isEuro !== undefined && `${isEuro ? "Euro" : "American"} `}
            {selectedOption.isPut ? "Put" : "Call"}
          </div>
        </div>

        <div className="mb-2 text-sm text-gray-500">
          <span className="text-white tabular-nums">${formatMoney(pricePerOption)}</span>{" "}
          per option
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
              <span className="pr-2 text-[10px] text-gray-500 uppercase tracking-wider">USDC</span>
            </div>
            {(() => {
              const tradeBtn = (
                <button
                  type="button"
                  onClick={handleTrade}
                  disabled={
                    !quote ||
                    isTrading ||
                    (approvals.allSatisfied && !!insufficientMessage)
                  }
                  className="shrink-0 h-7 px-3 rounded-lg text-white text-base leading-none font-semibold disabled:opacity-50 transition-colors bg-blue-500 hover:bg-blue-400"
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
              );
              return disabledReason ? (
                <Hint tip={disabledReason} above underline={false}>
                  {tradeBtn}
                </Hint>
              ) : (
                tradeBtn
              );
            })()}
          </div>
        </div>

        {insufficientMessage && (
          <div className="mt-2 text-xs text-amber-300/90">{insufficientMessage}</div>
        )}

        <div className="mt-3 flex items-center">
          <button
            type="button"
            onClick={() => setShowApprovalsModal(true)}
            className="ml-auto text-xs text-gray-400 hover:text-white underline underline-offset-2"
          >
            approvals
            {approvals.allSatisfied
              ? " ✓"
              : ` (${[
                  approvals.needsUsdcApproval,
                  approvals.needsOptionApproval,
                  approvals.needsAutoMint,
                  approvals.needsCollateralApproval,
                ].filter(Boolean).length} needed)`}
          </button>
        </div>

        {tradeError && <div className="mt-2 text-xs text-red-400">{tradeError}</div>}
        {txHash && <div className="mt-2 text-xs text-gray-400 font-mono break-all">tx {txHash}</div>}
        </div>

        {/* Right side: token selector + spot, balances, holdings */}
        <div className="w-[12rem] shrink-0 flex flex-col gap-3 border-l border-gray-700/40 pl-4">
          <div className="flex flex-col items-start gap-1">
            {tokenSelector}
            {spotPrice !== undefined && (
              <span className="text-xs text-gray-400">
                spot <span className="text-white tabular-nums">${formatMoney(spotPrice)}</span>
              </span>
            )}
          </div>
          {balances.length > 0 && (
            <div className="pt-2 border-t border-gray-700/40">
              <div className="text-[11px] uppercase tracking-wider text-gray-400 font-semibold mb-2">
                Balances
              </div>
              <ul className="flex flex-col gap-1 text-sm tabular-nums">
                {balances.map(b => (
                  <li key={b.label} className="flex items-center justify-between gap-2 min-w-0">
                    <span className="text-gray-500 text-xs uppercase tracking-wider truncate">{b.label}</span>
                    <span className={b.dim ? "text-gray-500" : "text-blue-100"}>{b.value}</span>
                  </li>
                ))}
              </ul>
            </div>
          )}
          <div className="pt-2 border-t border-gray-700/40">{holdings}</div>
        </div>
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

      {showApprovalsModal && (
        <ApprovalsModal
          steps={steps}
          direction={direction}
          collLabel={collSymbol}
          onClose={() => setShowApprovalsModal(false)}
        />
      )}
    </div>
  );
}

interface ApprovalsModalProps {
  steps: Array<{
    label: string;
    done: boolean;
    partial?: boolean;
    pending: boolean;
    onAction?: () => void;
    title?: string;
  }>;
  direction: TradeDirection;
  collLabel: string;
  onClose: () => void;
}

/**
 * Approvals walkthrough surfaced when the user clicks Buy/Sell before
 * granting them. Mirrors /yield's ApprovalsModal — backdrop click-to-close,
 * inline Approve buttons, longer per-row descriptions.
 */
function ApprovalsModal({ steps, direction, collLabel, onClose }: ApprovalsModalProps) {
  const allDone = steps.every(s => s.done);
  return (
    <div
      className="fixed inset-0 z-50 bg-black/70 flex items-center justify-center p-4"
      onClick={onClose}
    >
      <div
        className="bg-black border border-[#FF8300]/40 rounded-xl p-5 max-w-md w-full shadow-2xl"
        onClick={e => e.stopPropagation()}
      >
        <div className="flex items-center justify-between mb-3">
          <div className="text-xs font-semibold uppercase tracking-wider text-gray-200">
            Approvals to {direction === "buy" ? "buy" : "sell"}
          </div>
          <button
            type="button"
            onClick={onClose}
            aria-label="Close"
            className="text-gray-400 hover:text-white text-base leading-none"
          >
            ×
          </button>
        </div>
        <p className="text-xs text-gray-400 mb-4 leading-relaxed">
          Each row is a one-time signature so the protocol can move the right tokens on your
          behalf. Once granted, future {direction === "buy" ? "buys" : "sells"} against the same
          {" "}{collLabel} skip these prompts. Selling to the market maker also needs the
          auto-mint + {collLabel} pair so the option can be minted from your collateral and sold
          in a single transaction.
        </p>
        <ul className="flex flex-col gap-3">
          {steps.map(step => (
            <li key={step.label} className="flex flex-col gap-1">
              <div className="flex items-center gap-2">
                {step.done ? (
                  <span className="inline-flex items-center justify-center min-w-[3rem] text-emerald-400 text-base">
                    ✓
                  </span>
                ) : (
                  <button
                    type="button"
                    onClick={step.onAction}
                    disabled={step.pending || !step.onAction}
                    className={`inline-flex items-center justify-center min-w-[3rem] px-2 py-0.5 rounded-md text-black text-xs font-semibold disabled:opacity-50 transition-colors ${
                      step.partial
                        ? "bg-pink-500 hover:bg-pink-400"
                        : "bg-[#FF8300] hover:bg-[#e07400]"
                    }`}
                  >
                    {step.pending ? "…" : "Approve"}
                  </button>
                )}
                <span className={`font-semibold ${step.done ? "text-gray-500" : "text-gray-100"}`}>
                  {step.label}
                </span>
              </div>
              {step.title && (
                <p className="ml-[3.5rem] text-xs text-gray-400 leading-relaxed">{step.title}</p>
              )}
            </li>
          ))}
        </ul>
        {allDone && (
          <div className="mt-4 pt-3 border-t border-gray-800 text-center">
            <button
              type="button"
              onClick={onClose}
              className="px-4 py-1.5 rounded-md bg-[#2F50FF] hover:bg-[#35F3FF] hover:text-black text-white text-sm font-semibold transition-colors"
            >
              All set — close
            </button>
          </div>
        )}
      </div>
    </div>
  );
}

