import { useEffect, useMemo, useState } from "react";
import { formatUnits } from "viem";
import { useAccount } from "wagmi";
import { useReadOptionBalancesOf } from "~~/generated";
import { useTokenSpot } from "../../lib/useTokenSpot";
import { useTokenMap } from "../../mint/hooks/useTokenMap";
import { useDirectPrices } from "../../trade/hooks/useDirectPrices";
import { type TradableOption, useTradableOptions } from "../../trade/hooks/useTradableOptions";
import { STABLECOINS, type UnderlyingToken } from "../data";
import { useSellApprovals } from "../hooks/useSellApprovals";
import { ApprovalsList } from "../../components/ApprovalsList";
import { BuyBackRow } from "../../components/options/BuyBackButton";
import { Hint } from "../../components/Hint";
import { useAllHeldOptions } from "../../trade/hooks/useAllHeldOptions";
import { PositionsCard } from "./PositionsCard";
import { StablecoinTabs } from "./StablecoinTabs";
import { useReadOptionIsEuro } from "~~/generated";
import { SellPanel } from "./SellPanel";
import { StrikeExpirationGrid } from "./StrikeExpirationGrid";

interface YieldPanelProps {
  mode: "calls" | "puts";
  onModeChange: (m: "calls" | "puts") => void;
  token: UnderlyingToken;
  stablecoin?: string;
  onStablecoinChange?: (s: string) => void;
  /** Optional element rendered as the right-side token pill (the underlying
   *  TokenGrid in compact mode, mirroring /trade's pattern). */
  tokenSelector?: React.ReactNode;
}

export function YieldPanel({
  mode,
  onModeChange,
  token,
  stablecoin,
  onStablecoinChange,
  tokenSelector,
}: YieldPanelProps) {
  const { allTokensMap } = useTokenMap();
  const stable = STABLECOINS.find(s => s.symbol === stablecoin);
  const tokenAddress = allTokensMap[token.symbol]?.address ?? null;
  const stableAddress = stable ? allTokensMap[stable.symbol]?.address ?? null : null;

  const { data: rawOptions, isLoading } = useTradableOptions(tokenAddress);
  const { data: prices } = useDirectPrices();
  const [selected, setSelected] = useState<TradableOption | null>(null);
  const [amount, setAmount] = useState("1");

  const options = useMemo(() => {
    if (!rawOptions) return [];
    const tokenAddr = tokenAddress?.toLowerCase();
    const stableAddr = stableAddress?.toLowerCase();
    return rawOptions.filter(o => {
      const coll = o.collateralAddress.toLowerCase();
      const cons = o.considerationAddress.toLowerCase();
      if (mode === "calls") {
        return coll === tokenAddr;
      }
      return coll === stableAddr && cons === tokenAddr;
    });
  }, [rawOptions, mode, tokenAddress, stableAddress]);

  const subtitle =
    mode === "calls"
      ? `Write covered calls against your ${token.symbol}`
      : `Write covered puts — deposit ${stable?.symbol ?? stablecoin}, strike-buy ${token.symbol}`;

  // Spot from DeFiLlama (frontend, chain-agnostic). Falls back to the MM's
  // per-option spot echo only if DeFiLlama is unavailable.
  const llamaSpot = useTokenSpot(token.symbol);
  const spot = (() => {
    if (llamaSpot !== undefined) return llamaSpot;
    if (!prices) return undefined;
    for (const o of options) {
      const p = prices.get(o.optionAddress.toLowerCase())?.spotPrice;
      if (p !== undefined && Number.isFinite(p)) return p;
    }
    return undefined;
  })();
  const spotDisplay =
    spot === undefined
      ? null
      : spot >= 1000
        ? spot.toLocaleString(undefined, { maximumFractionDigits: 0 })
        : spot.toLocaleString(undefined, { maximumFractionDigits: 2 });

  const displayStrikeOf = (o: TradableOption) =>
    o.isPut && o.strike > 0n ? Number(formatUnits(10n ** 36n / o.strike, 18)) : Number(formatUnits(o.strike, 18));

  // Strike window: OTM side of spot, within ±100% (i.e. strike differs from
  // spot by no more than 100% of spot). Calls = (spot, 2·spot]; puts = [0, spot).
  // Expirations must be at least 5 days out.
  const gridOptions = useMemo(() => {
    if (spot === undefined) return options;
    const upper = spot * 2;
    const minExpiry = BigInt(Math.floor(Date.now() / 1000) + 5 * 24 * 3600);
    return options.filter(o => {
      if (o.expiration < minExpiry) return false;
      const s = displayStrikeOf(o);
      if (!Number.isFinite(s)) return false;
      return mode === "calls" ? s > spot && s <= upper : s < spot && s >= 0;
    });
  }, [options, spot, mode]);

  // Auto-select the latest-expiry / closest-to-spot-OTM cell whenever the grid
  // changes and the current selection isn't in it. "Closest to spot" = lowest
  // strike for calls (strikes are above spot) and highest strike for puts
  // (strikes are below spot) — in both cases, the fattest-premium OTM option.
  useEffect(() => {
    if (gridOptions.length === 0) return;
    if (selected && gridOptions.some(o => o.optionAddress === selected.optionAddress)) return;
    let best = gridOptions[0];
    const closerToSpot = (a: TradableOption, b: TradableOption) =>
      mode === "calls" ? displayStrikeOf(a) < displayStrikeOf(b) : displayStrikeOf(a) > displayStrikeOf(b);
    for (const o of gridOptions) {
      if (o.expiration > best.expiration) best = o;
      else if (o.expiration === best.expiration && closerToSpot(o, best)) best = o;
    }
    setSelected(best);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [gridOptions, mode]);

  const approvals = useSellApprovals(selected, amount);
  // Tap the same hook PositionsCard uses so we can decide whether to render
  // the Positions column (and its dividing wrapper) at all.
  const { held: allHeld } = useAllHeldOptions();
  const hasOpenPositions = allHeld.some(h => h.receiptBalance > 0n);

  // Option.balancesOf(user) returns (collateral, consideration, option, coll) in a single call.
  const { address: userAddress } = useAccount();
  const { data: optionBalances } = useReadOptionBalancesOf({
    address: (selected?.optionAddress as `0x${string}` | undefined) ?? undefined,
    args: userAddress ? [userAddress] : undefined,
    query: { enabled: !!userAddress && !!selected },
  });
  const { data: isEuro } = useReadOptionIsEuro({
    address: (selected?.optionAddress as `0x${string}` | undefined) ?? undefined,
    query: { enabled: !!selected },
  });

  const balanceRows = useMemo(() => {
    if (!selected || !optionBalances) return undefined;
    const collAddr = selected.collateralAddress.toLowerCase();
    const consAddr = selected.considerationAddress.toLowerCase();
    const lookup = (addr: string) =>
      Object.values(allTokensMap).find(t => t.address.toLowerCase() === addr);
    const coll = lookup(collAddr);
    const cons = lookup(consAddr);
    const fmt = (raw: bigint, decimals: number | undefined) => {
      if (decimals === undefined) return raw.toString();
      const n = Number(formatUnits(raw, decimals));
      if (n === 0) return "0";
      if (n >= 1) return n.toLocaleString(undefined, { maximumFractionDigits: 2 });
      if (n >= 0.0001) return n.toFixed(4);
      return n.toPrecision(2);
    };
    return [
      {
        label: coll?.symbol ?? "Collateral",
        value: fmt(optionBalances.collateral, coll?.decimals),
        dim: optionBalances.collateral === 0n,
      },
      {
        label: cons?.symbol ?? "Consideration",
        value: fmt(optionBalances.consideration, cons?.decimals),
        dim: optionBalances.consideration === 0n,
      },
      {
        label: "Short",
        value: fmt(optionBalances.receipt, approvals.optionDecimals),
        dim: optionBalances.receipt === 0n,
        bottomRow: (
          <BuyBackRow
            optionAddress={selected.optionAddress as `0x${string}`}
            shortAmount={optionBalances.receipt}
          />
        ),
      },
    ];
  }, [selected, optionBalances, allTokensMap, approvals.optionDecimals]);

  const collLabel = mode === "calls" ? token.symbol : stable?.symbol ?? "USDC";
  const approvalSteps = [
    {
      label: `Auto Covered ${mode === "calls" ? "Call" : "Put"}`,
      done: approvals.autoMintEnabled === true,
      pending: approvals.isEnablingAutoMint,
      onAction: approvals.handleEnableAutoMint,
      title: `Lets the factory mint the option/receipt pair from your ${collLabel} collateral atomically when Bebop fills your write — no manual mint step.`,
    },
    {
      label: collLabel,
      done: !approvals.needsCollateralApproval,
      partial: approvals.collateralPartial,
      pending: approvals.isApproving,
      onAction: approvals.handleApproveCollateral,
      title: `Two layers: first ERC20.approve(factory) so the factory can move ${collLabel} from your wallet, then factory.approve(${collLabel}) to authorise the factory's internal pull on auto-mint. Click Approve once for each layer.`,
    },
    {
      label: "Option",
      done: !approvals.needsOptionApproval,
      pending: approvals.isApproving,
      onAction: approvals.handleApproveOption,
      title: approvals.factoryOperatorApproved
        ? "Covered by your factory-operator approval — Bebop can pull option tokens for any option."
        : "Approve the option ERC20 to Bebop so it can pull the freshly-minted long when settling your write.",
    },
    {
      label: "USDC",
      done: !approvals.needsUsdcApproval,
      pending: approvals.isApproving,
      onAction: approvals.handleApproveUsdc,
      title: "Lets you buy back / close the short later via Bebop without another approval round-trip.",
    },
  ];
  const [showApprovalsModal, setShowApprovalsModal] = useState(false);

  const optionDescriptor = selected ? (
    <div className="text-base font-semibold text-white tabular-nums leading-tight">
      <div>
        {(() => {
          const strike = displayStrikeOf(selected);
          return strike >= 1
            ? `$${strike.toLocaleString(undefined, { maximumFractionDigits: 2 })}`
            : `$${strike.toPrecision(2)}`;
        })()}{" "}
        ·{" "}
        {new Date(Number(selected.expiration) * 1000).toLocaleDateString(undefined, {
          month: "short",
          day: "numeric",
          year: "numeric",
          timeZone: "UTC",
        })}
      </div>
      <div>
        {isEuro !== undefined && `${isEuro ? "Euro" : "American"} `}
        {selected.isPut ? "Put" : "Call"}
      </div>
    </div>
  ) : (
    <div className="text-base font-semibold text-gray-500">Pick a strike below…</div>
  );

  return (
    <div className="inline-block max-w-full text-left">
      <div className="w-full flex flex-wrap gap-3 items-stretch justify-center">
        {/* Action card: 28rem with left/right split, mirroring /trade's TradePanel */}
        <div className="rounded-xl border border-[#2F50FF]/40 bg-gradient-to-b from-[#2F50FF]/10 to-black/60 shadow-lg px-5 py-4 w-fit min-w-[28rem] flex gap-5">
          {/* LEFT */}
          <div className="flex-1 min-w-0 flex flex-col">
            <ModeHeader
              mode={mode}
              onModeChange={onModeChange}
              subtitle={subtitle}
              stablecoin={stablecoin}
              onStablecoinChange={onStablecoinChange}
            />
            <div className="mb-4">{optionDescriptor}</div>

            <SellPanel
              option={selected}
              depositSymbol={mode === "calls" ? token.symbol : stable?.symbol ?? "USDC"}
              underlyingSymbol={token.symbol}
              stableSymbol={mode === "puts" ? stable?.symbol ?? "USDC" : "USDC"}
              mode={mode}
              amount={amount}
              onAmountChange={setAmount}
              approvals={approvals}
              onRequestApprovals={() => setShowApprovalsModal(true)}
              hideDescriptor
            />
          </div>

          {/* RIGHT: token + spot, balances, buy-back */}
          <div className="w-[12rem] shrink-0 flex flex-col gap-4 border-l border-gray-700/40 pl-5">
            <div className="flex flex-col items-start gap-1">
              {tokenSelector}
              {spotDisplay && (
                <span className="text-xs text-gray-400">
                  spot <span className="text-white tabular-nums">${spotDisplay}</span>
                </span>
              )}
            </div>

            {balanceRows && (
              <div className="pt-2 border-t border-gray-700/40">
                <div className="text-[11px] uppercase tracking-wider text-gray-400 font-semibold mb-2">
                  Balances
                </div>
                <ul className="flex flex-col gap-1.5 text-sm tabular-nums">
                  {balanceRows.map(b => (
                    <li key={b.label} className="flex flex-col gap-1">
                      <div className="flex items-center justify-between gap-2 min-w-0">
                        <span className="text-gray-500 text-xs uppercase tracking-wider truncate">
                          {b.label}
                        </span>
                        <span className={b.dim ? "text-gray-500" : "text-white"}>{b.value}</span>
                      </div>
                      {b.bottomRow && <div className="pl-2">{b.bottomRow}</div>}
                    </li>
                  ))}
                </ul>
              </div>
            )}
          </div>

          {/* THIRD COLUMN: Open positions, only when the user has any. */}
          {hasOpenPositions && (
            <div className="w-[14rem] shrink-0 border-l border-gray-700/40 pl-5">
              <PositionsCard bare hideEmpty />
            </div>
          )}
        </div>
      </div>

      {/* Strike grid sits below the panel — same vertical order as /trade. */}
      <div className="mt-4">
        <StrikeExpirationGrid
          options={gridOptions}
          loading={isLoading}
          selectedAddress={selected?.optionAddress ?? null}
          onSelect={setSelected}
          prices={prices}
        />
      </div>

      {showApprovalsModal && (
        <ApprovalsModal
          steps={approvalSteps}
          onClose={() => setShowApprovalsModal(false)}
          mode={mode}
          collLabel={collLabel}
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
    title: string;
  }>;
  mode: "calls" | "puts";
  collLabel: string;
  onClose: () => void;
}

/**
 * One-time approvals walkthrough surfaced when the user clicks Deposit
 * before granting them. Mirrors the side ApprovalsList but with longer
 * explanations and the actions inline.
 */
function ApprovalsModal({ steps, mode, collLabel, onClose }: ApprovalsModalProps) {
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
            Approvals to deposit
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
          behalf. Once granted, future writes against the same {collLabel} skip these prompts.
          Covered {mode === "calls" ? "calls" : "puts"} need all of them so the option can be
          minted from your collateral and sold to the market maker in a single transaction.
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
              <p className="ml-[3.5rem] text-xs text-gray-400 leading-relaxed">{step.title}</p>
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

interface ModeHeaderProps {
  mode: "calls" | "puts";
  onModeChange: (m: "calls" | "puts") => void;
  subtitle: string;
  stablecoin?: string;
  onStablecoinChange?: (s: string) => void;
}

/**
 * Compact mode/strategy header. Reads as "Covered Call ▾" with a hover
 * tooltip carrying the long-form subtitle, and clicks open a small inline
 * panel to switch between Calls/Puts (and pick a stablecoin in puts mode).
 */
function ModeHeader({ mode, onModeChange, subtitle, stablecoin, onStablecoinChange }: ModeHeaderProps) {
  const [open, setOpen] = useState(false);
  const label = `Covered ${mode === "calls" ? "Call" : "Put"}`;

  return (
    <div className="relative mb-1">
      <div className="flex items-center gap-1">
        <Hint tip={subtitle} width="w-72" underline={false}>
          <button
            type="button"
            onClick={() => setOpen(o => !o)}
            className="inline-flex items-center gap-1 px-2 py-0.5 rounded-md border border-gray-700 bg-black/40 hover:border-gray-500 hover:bg-black/60 text-[11px] uppercase tracking-wider text-gray-300 transition-colors"
          >
            {label}
            <span className="text-gray-500" aria-hidden>▾</span>
          </button>
        </Hint>
      </div>
      {open && (
        <div className="absolute top-full left-0 z-30 mt-1 p-2 rounded-lg border border-gray-700 bg-black/95 shadow-xl flex flex-col gap-2">
          <div className="flex rounded-md border border-gray-700 overflow-hidden text-[11px]">
            <button
              type="button"
              onClick={() => {
                onModeChange("calls");
                setOpen(false);
              }}
              className={`px-2 py-0.5 ${mode === "calls" ? "bg-[#2F50FF] text-white" : "bg-black/40 text-gray-300 hover:bg-black/60"}`}
            >
              Calls
            </button>
            <button
              type="button"
              onClick={() => {
                onModeChange("puts");
                setOpen(false);
              }}
              className={`px-2 py-0.5 ${mode === "puts" ? "bg-[#2F50FF] text-white" : "bg-black/40 text-gray-300 hover:bg-black/60"}`}
            >
              Puts
            </button>
          </div>
          {mode === "puts" && stablecoin && onStablecoinChange && (
            <div onClick={() => setOpen(false)}>
              <StablecoinTabs selected={stablecoin} onSelect={onStablecoinChange} />
            </div>
          )}
        </div>
      )}
    </div>
  );
}
