import clsx from "clsx";
import { Fragment, useEffect, useMemo, useState } from "react";
import { usePricing } from "../../contexts/PricingContext";
import { formatStrikeValue } from "../../lib/strike";
import { useTokenSpot } from "../../lib/useTokenSpot";
import { useTokenMap } from "../../mint/hooks/useTokenMap";
import { useDirectPrices } from "../hooks/useDirectPrices";
import { type TradableOption, useTradableOptions } from "../hooks/useTradableOptions";
import { formatUnits } from "viem";

function CheckboxToggle({
  checked,
  onChange,
  label,
  accent,
}: {
  checked: boolean;
  onChange: () => void;
  label: string;
  /** Tailwind color suffix used for the checked state (e.g. "blue", "purple", "gray"). */
  accent: "blue" | "purple" | "gray";
}) {
  // Pre-build the class strings — Tailwind's JIT can't pick up dynamic
  // template-literal classes like `bg-${accent}-600`.
  const accentClasses = {
    blue: "bg-blue-600 border-blue-600",
    purple: "bg-purple-600 border-purple-600",
    gray: "bg-gray-500 border-gray-500",
  }[accent];
  const labelColor = checked ? "text-white" : "text-gray-400";
  return (
    <button
      type="button"
      onClick={onChange}
      className="flex items-center gap-2 px-2 py-1 rounded text-sm font-medium hover:bg-gray-800/60 transition-colors"
    >
      <span
        className={clsx(
          "inline-flex items-center justify-center w-4 h-4 rounded-sm border transition-colors",
          checked ? accentClasses : "border-gray-600 bg-transparent",
        )}
        aria-hidden
      >
        {checked && (
          <svg viewBox="0 0 12 12" width="10" height="10" fill="none">
            <path d="M2.5 6.2L4.8 8.5L9.5 3.8" stroke="white" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round" />
          </svg>
        )}
      </span>
      <span className={labelColor}>{label}</span>
    </button>
  );
}

export interface OptionSelection {
  option: TradableOption;
  isBuy: boolean; // true = buying option (user pays USDC), false = selling option (user receives USDC)
}

interface OptionsGridProps {
  selectedToken: string;
  onSelectOption: (selection: OptionSelection) => void;
  /** When set, highlights the matching cell as the active selection. */
  selected?: { optionAddress: string; isBuy: boolean } | null;
}

interface GridCell {
  call?: TradableOption;
  put?: TradableOption;
}

export function OptionsGrid({ selectedToken, onSelectOption, selected }: OptionsGridProps) {
  const [showCalls, setShowCalls] = useState(true);
  const [showPuts, setShowPuts] = useState(true);
  const [visibleExpirations, setVisibleExpirations] = useState<Set<string>>(new Set());

  const { data: options, isLoading } = useTradableOptions(selectedToken);

  // Use pricing from context (connection is managed at layout level)
  const { getPrice } = usePricing();

  // Fallback prices polled from the direct quote server. Used for cells where
  // the WebSocket stream has no quote (typical when the relay isn't reachable).
  const { data: directPrices } = useDirectPrices();

  // Spot for the strike-window filter. Resolve the picked token address to a
  // symbol via the chain's token map, then ask DeFiLlama. Independent of the
  // market-maker so the filter works on any chain whether or not the MM has
  // discovered options yet.
  const { allTokensMap } = useTokenMap();
  const selectedSymbol = useMemo(() => {
    const lower = selectedToken.toLowerCase();
    return Object.values(allTokensMap).find(t => t.address.toLowerCase() === lower)?.symbol;
  }, [allTokensMap, selectedToken]);
  const spotFromLlama = useTokenSpot(selectedSymbol);

  // Group options by strike and expiration
  const { strikes, expirations, grid, spot } = useMemo(() => {
    if (!options || options.length === 0) {
      return { strikes: [], expirations: [], grid: new Map<string, GridCell>(), spot: undefined };
    }

    // Strike window: ±100% of spot, i.e. |strike − spot| ≤ spot ⇒ strike ∈
    // [0, 2·spot]. Spot comes from DeFiLlama by underlying symbol; the MM's
    // per-option spot echo is used as a backup if DeFiLlama is rate-limited.
    let spot = spotFromLlama;
    if (spot === undefined) {
      for (const o of options) {
        const p = directPrices?.get(o.optionAddress.toLowerCase())?.spotPrice;
        if (p !== undefined && Number.isFinite(p) && p > 0) {
          spot = p;
          break;
        }
      }
    }

    const filteredOptions =
      spot === undefined
        ? options
        : options.filter(o => {
            const dispStrike = o.isPut && o.strike > 0n ? 10n ** 36n / o.strike : o.strike;
            const s = parseFloat(formatUnits(dispStrike, 18));
            return Number.isFinite(s) && Math.abs(s - spot!) <= spot!;
          });

    const strikesSet = new Set<string>();
    const expirationsSet = new Set<string>();
    const gridMap = new Map<string, GridCell>();

    filteredOptions.forEach(option => {
      // For puts, invert the strike price to align with calls
      let normalizedStrike = option.strike;
      if (option.isPut && option.strike > 0n) {
        normalizedStrike = 10n ** 36n / option.strike;
      }

      // Round strike to 2 decimal places
      const strikeFloat = parseFloat(formatUnits(normalizedStrike, 18));
      const strikeRounded = Math.round(strikeFloat * 100) / 100;
      const strikeRoundedBigInt = BigInt(Math.round(strikeRounded * 1e18));

      const strikeKey = strikeRoundedBigInt.toString();
      const expirationKey = option.expiration.toString();

      strikesSet.add(strikeKey);
      expirationsSet.add(expirationKey);

      const key = `${strikeKey}-${expirationKey}`;
      const cell = gridMap.get(key) || {};

      if (option.isPut) {
        cell.put = option;
      } else {
        cell.call = option;
      }

      gridMap.set(key, cell);
    });

    const sortedStrikes = Array.from(strikesSet).sort((a, b) => {
      return Number(BigInt(a) - BigInt(b));
    });

    const sortedExpirations = Array.from(expirationsSet).sort((a, b) => {
      return Number(BigInt(a) - BigInt(b));
    });

    return {
      strikes: sortedStrikes,
      expirations: sortedExpirations,
      grid: gridMap,
      spot,
    };
  }, [options, directPrices, spotFromLlama]);

  // Initialize visible expirations when expirations change
  useEffect(() => {
    if (expirations.length > 0 && visibleExpirations.size === 0) {
      setVisibleExpirations(new Set(expirations));
    }
  }, [expirations, visibleExpirations.size]);

  const toggleExpiration = (exp: string) => {
    setVisibleExpirations(prev => {
      const next = new Set(prev);
      if (next.has(exp)) {
        next.delete(exp);
      } else {
        next.add(exp);
      }
      return next;
    });
  };

  // Filter expirations to only show visible ones
  const filteredExpirations = expirations.filter(exp => visibleExpirations.has(exp));

  // Find the strike row index where the spot price line should sit. We
  // insert it *before* the first strike >= spot, so a spot of 2350 between
  // strikes 2300 and 2400 paints the line between those two rows. If spot
  // is below or above every strike (or unknown) we don't render the line.
  const spotWei = spot !== undefined ? BigInt(Math.round(spot * 1e18)) : undefined;
  const spotInsertIndex =
    spotWei !== undefined ? strikes.findIndex(s => BigInt(s) >= spotWei) : -1;
  const showSpotLine = spotInsertIndex > 0 && spotInsertIndex < strikes.length;
  const totalCols =
    (showCalls ? filteredExpirations.length * 2 : 0) +
    1 +
    (showPuts ? filteredExpirations.length * 2 : 0);

  if (isLoading) {
    return <div className="text-blue-300">Loading options...</div>;
  }

  if (!options || options.length === 0) {
    return <div className="text-gray-400">No options available for this token</div>;
  }

  return (
    <div className="overflow-x-auto">
      {/* Filter row — Calls / Puts and expiration dates as a single group of
          checkbox-style toggles so it's obvious they multi-select. */}
      <div className="flex flex-wrap justify-center items-center gap-x-3 gap-y-1 mb-4">
        <CheckboxToggle checked={showCalls} onChange={() => setShowCalls(!showCalls)} label="Calls" accent="blue" />
        <CheckboxToggle checked={showPuts} onChange={() => setShowPuts(!showPuts)} label="Puts" accent="purple" />
        {expirations.map(exp => {
          const date = new Date(Number(exp) * 1000);
          const dateStr = date.toLocaleDateString(undefined, { month: "short", day: "numeric" });
          return (
            <CheckboxToggle
              key={exp}
              checked={visibleExpirations.has(exp)}
              onChange={() => toggleExpiration(exp)}
              label={dateStr}
              accent="gray"
            />
          );
        })}
      </div>

      {/* w-auto + mx-auto: cells size to content (no padding stretch on wide
          windows), and the table sits centered in its scrollable wrapper. */}
      <table className="w-auto mx-auto border-collapse text-sm">
        <thead>
          {/* Top header row - CALLS | Strike | PUTS */}
          <tr className="border-b border-gray-700">
            {showCalls && (
              <th
                colSpan={filteredExpirations.length * 2}
                className="p-2 text-center text-blue-400 bg-blue-900/20 border-r border-gray-700"
              >
                CALLS
              </th>
            )}
            <th rowSpan={2} className="p-2 text-center text-gray-400 bg-gray-900/50 w-24">
              Strike
            </th>
            {showPuts && (
              <th
                colSpan={filteredExpirations.length * 2}
                className="p-2 text-center text-purple-400 bg-purple-900/20 border-l border-gray-700"
              >
                PUTS
              </th>
            )}
          </tr>
          {/* Second header row - expiration dates with Bid/Ask */}
          <tr className="border-b border-gray-700">
            {showCalls &&
              filteredExpirations.map(exp => {
                const date = new Date(Number(exp) * 1000);
                const dateStr = date.toLocaleDateString(undefined, { month: "short", day: "numeric" });
                return (
                  <th key={`call-${exp}`} colSpan={2} className="p-1 text-center border-r border-gray-800">
                    <div className="text-gray-400 text-xs">{dateStr}</div>
                    <div className="flex text-[10px] mt-1">
                      <span className="flex-1 text-orange-400">Bid</span>
                      <span className="flex-1 text-blue-400">Ask</span>
                    </div>
                  </th>
                );
              })}
            {showPuts &&
              filteredExpirations.map(exp => {
                const date = new Date(Number(exp) * 1000);
                const dateStr = date.toLocaleDateString(undefined, { month: "short", day: "numeric" });
                return (
                  <th key={`put-${exp}`} colSpan={2} className="p-1 text-center border-l border-gray-800">
                    <div className="text-gray-400 text-xs">{dateStr}</div>
                    <div className="flex text-[10px] mt-1">
                      <span className="flex-1 text-orange-400">Bid</span>
                      <span className="flex-1 text-blue-400">Ask</span>
                    </div>
                  </th>
                );
              })}
          </tr>
        </thead>
        <tbody>
          {strikes.map((strike, idx) => {
            const strikeFormatted = formatStrikeValue(BigInt(strike));
            const renderSpotLine = showSpotLine && idx === spotInsertIndex;

            return (
              <Fragment key={strike}>
                {renderSpotLine && (
                  <tr aria-label={`spot price ${spot}`}>
                    <td colSpan={totalCols} className="p-0">
                      <div className="relative h-0 border-t border-emerald-400/70">
                        <span className="absolute -top-[9px] left-1/2 -translate-x-1/2 px-2 text-[10px] font-semibold uppercase tracking-wider text-emerald-300 bg-black">
                          spot ${spot !== undefined ? spot.toLocaleString(undefined, { maximumFractionDigits: 2 }) : ""}
                        </span>
                      </div>
                    </td>
                  </tr>
                )}
                <tr className="border-b border-gray-800">
                {/* Call columns for each expiration */}
                {showCalls &&
                  filteredExpirations.map(exp => {
                    const key = `${strike}-${exp}`;
                    const cell = grid.get(key);
                    const callPrice = cell?.call ? getPrice(cell.call.optionAddress) : undefined;
                    const directCall = cell?.call ? directPrices?.get(cell.call.optionAddress.toLowerCase()) : undefined;
                    const callBid = callPrice?.bids[0]?.[0] ?? directCall?.bid;
                    const callAsk = callPrice?.asks[0]?.[0] ?? directCall?.ask;

                    return (
                      <td key={`call-${exp}`} colSpan={2} className="p-0 border-r border-gray-800">
                        <div className="flex">
                          <PriceCell
                            opt={cell?.call}
                            price={callBid}
                            isBuy={false}
                            selected={selected}
                            onSelect={onSelectOption}
                          />
                          <PriceCell
                            opt={cell?.call}
                            price={callAsk}
                            isBuy={true}
                            selected={selected}
                            onSelect={onSelectOption}
                          />
                        </div>
                      </td>
                    );
                  })}

                {/* Strike */}
                <td className="p-2 text-right text-white font-medium bg-gray-900/50 tabular-nums">${strikeFormatted}</td>

                {/* Put columns for each expiration */}
                {showPuts &&
                  filteredExpirations.map(exp => {
                    const key = `${strike}-${exp}`;
                    const cell = grid.get(key);
                    const putPrice = cell?.put ? getPrice(cell.put.optionAddress) : undefined;
                    const directPut = cell?.put ? directPrices?.get(cell.put.optionAddress.toLowerCase()) : undefined;
                    const putBid = putPrice?.bids[0]?.[0] ?? directPut?.bid;
                    const putAsk = putPrice?.asks[0]?.[0] ?? directPut?.ask;

                    return (
                      <td key={`put-${exp}`} colSpan={2} className="p-0 border-l border-gray-800">
                        <div className="flex">
                          <PriceCell
                            opt={cell?.put}
                            price={putBid}
                            isBuy={false}
                            selected={selected}
                            onSelect={onSelectOption}
                          />
                          <PriceCell
                            opt={cell?.put}
                            price={putAsk}
                            isBuy={true}
                            selected={selected}
                            onSelect={onSelectOption}
                          />
                        </div>
                      </td>
                    );
                  })}
                </tr>
              </Fragment>
            );
          })}
        </tbody>
      </table>
    </div>
  );
}

/**
 * One bid/ask price slot. Bids paint orange, asks paint blue. The "box"
 * (border + background) is reserved for the active selection so the user can
 * see at a glance which spot on the grid feeds the trade panel above.
 */
function PriceCell({
  opt,
  price,
  isBuy,
  selected,
  onSelect,
}: {
  opt: TradableOption | undefined;
  price: number | undefined;
  isBuy: boolean;
  selected: { optionAddress: string; isBuy: boolean } | null | undefined;
  onSelect: (s: OptionSelection) => void;
}) {
  if (!opt) {
    return (
      <div className="flex-1 p-0.5">
        <span className="block text-center text-gray-700 text-xs py-1">—</span>
      </div>
    );
  }
  const active =
    selected?.optionAddress.toLowerCase() === opt.optionAddress.toLowerCase() && selected.isBuy === isBuy;
  // Bid + Ask both render white for a quieter grid; the active/hover box still
  // distinguishes the two via colour.
  const colour = "text-white/90 hover:text-white";
  // Same fill+border on hover as on active, so the hovered cell previews
  // exactly what selecting it will look like. Transparent default border
  // reserves the 1px so hovering doesn't nudge the layout.
  const activeBox = isBuy
    ? "bg-blue-900/30 border-blue-500"
    : "bg-orange-900/30 border-orange-500";
  const hoverBox = isBuy
    ? "hover:bg-blue-900/30 hover:border-blue-500"
    : "hover:bg-orange-900/30 hover:border-orange-500";
  const title = `${isBuy ? "Buy" : "Sell"} ${opt.isPut ? "Put" : "Call"}`;
  return (
    <div className="flex-1 p-0.5">
      <button
        onClick={() => onSelect({ option: opt, isBuy })}
        title={title}
        className={`w-full px-2 py-1 rounded border border-transparent transition-colors text-xs tabular-nums text-right ${colour} ${
          active ? activeBox : hoverBox
        }`}
      >
        {price !== undefined ? price.toFixed(2) : "—"}
      </button>
    </div>
  );
}
