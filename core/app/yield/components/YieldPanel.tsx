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
import { useReadOptionIsEuro } from "~~/generated";
import { SellPanel } from "./SellPanel";
import { StrikeExpirationGrid } from "./StrikeExpirationGrid";

interface YieldPanelProps {
  mode: "calls" | "puts";
  token: UnderlyingToken;
  stablecoin?: string;
  /** Optional element rendered as the right-side token pill (the underlying
   *  TokenGrid in compact mode, mirroring /trade's pattern). */
  tokenSelector?: React.ReactNode;
}

export function YieldPanel({ mode, token, stablecoin, tokenSelector }: YieldPanelProps) {
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
        <div className="rounded-xl border border-[#2F50FF]/40 bg-gradient-to-b from-[#2F50FF]/10 to-black/60 shadow-lg px-4 py-3 w-[28rem] flex gap-4">
          {/* LEFT */}
          <div className="flex-1 min-w-0 flex flex-col">
            <div className="mb-1">
              <Hint tip={subtitle} width="w-72">
                <span className="text-[11px] uppercase tracking-wider text-gray-300">
                  {mode === "calls" ? "Covered Call" : "Covered Put"}
                </span>
              </Hint>
            </div>
            <div className="mb-3">{optionDescriptor}</div>

            <SellPanel
              option={selected}
              depositSymbol={mode === "calls" ? token.symbol : stable?.symbol ?? "USDC"}
              underlyingSymbol={token.symbol}
              stableSymbol={mode === "puts" ? stable?.symbol ?? "USDC" : "USDC"}
              mode={mode}
              amount={amount}
              onAmountChange={setAmount}
              approvals={approvals}
              hideDescriptor
            />
          </div>

          {/* RIGHT: token + spot, balances, buy-back */}
          <div className="w-[12rem] shrink-0 flex flex-col gap-3 border-l border-gray-700/40 pl-4">
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
        </div>

        {/* Trading Approvals column */}
        <div className="w-[16rem] rounded-lg border border-[#FF8300]/40 bg-[#FF8300]/5 p-3 self-start">
          <div className="text-[11px] uppercase tracking-wider text-gray-400 font-semibold mb-2">
            <Hint
              width="w-72"
              tip={[
                <span key="auto">
                  <b className="text-gray-100">Auto Covered {mode === "calls" ? "Call" : "Put"}</b>
                  {" "}— let the factory mint the option/receipt pair from your collateral atomically when Bebop fills your write.
                </span>,
                <span key="coll">
                  <b className="text-gray-100">{mode === "calls" ? token.symbol : stable?.symbol ?? "USDC"}</b>
                  {" "}— let the factory pull collateral on write.
                </span>,
                <span key="opt">
                  <b className="text-gray-100">Option</b> — let Bebop pull the freshly-minted long on settlement.
                </span>,
                <span key="usdc">
                  <b className="text-gray-100">USDC</b> — required only if you ever want to buy back to close.
                </span>,
              ]}
            >
              Trading Approvals
            </Hint>
          </div>
          <ApprovalsList
            steps={[
              {
                label: `Auto Covered ${mode === "calls" ? "Call" : "Put"}`,
                done: approvals.autoMintEnabled === true,
                pending: approvals.isEnablingAutoMint,
                onAction: approvals.handleEnableAutoMint,
                title: `Lets the factory mint the option/receipt pair from your ${mode === "calls" ? token.symbol : stable?.symbol ?? "USDC"} collateral atomically when Bebop fills your write — no manual mint step.`,
              },
              {
                label: mode === "calls" ? token.symbol : stable?.symbol ?? "USDC",
                done: !approvals.needsCollateralApproval,
                pending: approvals.isApproving,
                onAction: approvals.handleApproveCollateral,
                title: `Approve ${mode === "calls" ? token.symbol : stable?.symbol ?? "USDC"} so the factory can pull collateral on write.`,
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
            ]}
          />
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
    </div>
  );
}
