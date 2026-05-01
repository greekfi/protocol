import { useEffect, useMemo, useState } from "react";
import { formatUnits } from "viem";
import { useAccount } from "wagmi";
import { useReadOptionBalancesOf } from "~~/generated";
import { useTokenMap } from "../../mint/hooks/useTokenMap";
import { useDirectPrices } from "../../trade/hooks/useDirectPrices";
import { type TradableOption, useTradableOptions } from "../../trade/hooks/useTradableOptions";
import { STABLECOINS, type UnderlyingToken } from "../data";
import { useSellApprovals } from "../hooks/useSellApprovals";
import { ApprovalsCard } from "../../components/options/ApprovalsCard";
import { BuyBackRow } from "../../components/options/BuyBackButton";
import { SellPanel } from "./SellPanel";
import { StrikeExpirationGrid } from "./StrikeExpirationGrid";

interface YieldPanelProps {
  mode: "calls" | "puts";
  token: UnderlyingToken;
  stablecoin?: string;
  onClose: () => void;
}

export function YieldPanel({ mode, token, stablecoin, onClose }: YieldPanelProps) {
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

  // Spot price is reported per option by the MM; for a given underlying they're all equal,
  // so just pick the first priced option to display it in the header.
  const spot = (() => {
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

  return (
    <div className="inline-block max-w-full">
      <div className="mb-4">
        <StrikeExpirationGrid
          options={gridOptions}
          loading={isLoading}
          selectedAddress={selected?.optionAddress ?? null}
          onSelect={setSelected}
          prices={prices}
        />
      </div>

      <div className="flex flex-wrap gap-4 items-stretch">
        <div className="rounded-xl border border-[#2F50FF]/40 bg-gradient-to-b from-[#2F50FF]/10 to-black/60 shadow-lg px-4 py-3 max-w-md">
          <div className="flex items-start justify-between gap-4">
            <div>
              <span
                tabIndex={0}
                className="group relative inline-block text-xs uppercase tracking-wider text-[#35F3FF] mb-1 cursor-help focus:outline-none"
                aria-label={subtitle}
              >
                {mode === "calls" ? "Covered Call" : "Covered Put"}
                <span
                  role="tooltip"
                  className="pointer-events-none absolute left-0 top-full mt-1 w-64 p-2 rounded-lg border border-gray-700 bg-black/95 text-[11px] normal-case tracking-normal text-gray-300 shadow-lg opacity-0 invisible group-hover:opacity-100 group-hover:visible group-focus:opacity-100 group-focus:visible transition-opacity z-10"
                >
                  {subtitle}
                </span>
              </span>
              <h3 className="text-xl font-semibold text-blue-200">
                {token.symbol}
                {spotDisplay && (
                  <span className="ml-3 text-sm font-normal text-gray-400">
                    spot <span className="text-emerald-300 tabular-nums">${spotDisplay}</span>
                  </span>
                )}
              </h3>
            </div>
            <button
              type="button"
              onClick={onClose}
              className="text-gray-500 hover:text-gray-300 text-sm"
              aria-label="Close"
            >
              ✕
            </button>
          </div>

          <SellPanel
            option={selected}
            depositSymbol={mode === "calls" ? token.symbol : stable?.symbol ?? "USDC"}
            underlyingSymbol={token.symbol}
            stableSymbol={mode === "puts" ? stable?.symbol ?? "USDC" : "USDC"}
            mode={mode}
            amount={amount}
            onAmountChange={setAmount}
            approvals={approvals}
          />
        </div>

        <div className="w-72">
          <ApprovalsCard
            balances={balanceRows}
            steps={[
              {
                label: "Enable auto-mint on Factory",
                done: approvals.autoMintEnabled === true,
                pending: approvals.isEnablingAutoMint,
                onAction: approvals.handleEnableAutoMint,
                title:
                  "One-time per address — lets the Factory mint option tokens for you during Bebop settlement.",
              },
              {
                label: `Approve ${mode === "calls" ? token.symbol : stable?.symbol ?? "USDC"} to Factory`,
                done: !approvals.needsCollateralApproval,
                pending: approvals.isApproving,
                onAction: approvals.handleApproveCollateral,
                title: "Factory pulls the collateral from your wallet to mint the option tokens Bebop buys.",
              },
              {
                label: "Approve option to Bebop",
                done: !approvals.needsOptionApproval,
                pending: approvals.isApproving,
                onAction: approvals.handleApproveOption,
                title: approvals.factoryOperatorApproved
                  ? "Covered by your factory-operator approval."
                  : "Bebop pulls the option tokens from your wallet on settlement.",
              },
              {
                label: "Approve USDC to Bebop",
                done: !approvals.needsUsdcApproval,
                pending: approvals.isApproving,
                onAction: approvals.handleApproveUsdc,
                title: "Lets you buy back / close the position via Bebop later without another approval.",
              },
            ]}
          />
        </div>
      </div>
    </div>
  );
}
