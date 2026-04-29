import { useEffect, useMemo, useState } from "react";
import { usePricing } from "../../contexts/PricingContext";
import { formatStrikeValue } from "../../lib/strike";
import { useDirectPrices } from "../hooks/useDirectPrices";
import { type TradableOption, useTradableOptions } from "../hooks/useTradableOptions";
import { formatUnits } from "viem";

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

  // Group options by strike and expiration
  const { strikes, expirations, grid } = useMemo(() => {
    if (!options || options.length === 0) {
      return { strikes: [], expirations: [], grid: new Map<string, GridCell>() };
    }

    const strikesSet = new Set<string>();
    const expirationsSet = new Set<string>();
    const gridMap = new Map<string, GridCell>();

    options.forEach(option => {
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
    };
  }, [options]);

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

  if (isLoading) {
    return <div className="text-blue-300">Loading options...</div>;
  }

  if (!options || options.length === 0) {
    return <div className="text-gray-400">No options available for this token</div>;
  }

  return (
    <div className="overflow-x-auto">
      <div className="flex flex-wrap items-center gap-4 mb-4">
        <h2 className="text-xl font-light text-blue-300 mr-auto">Options Chain</h2>
        <div className="flex gap-2">
          <button
            onClick={() => setShowCalls(!showCalls)}
            className={`px-3 py-1.5 rounded text-sm font-medium transition-colors ${
              showCalls ? "bg-blue-600 text-white" : "bg-gray-800 text-gray-400 border border-gray-600"
            }`}
          >
            Calls
          </button>
          <button
            onClick={() => setShowPuts(!showPuts)}
            className={`px-3 py-1.5 rounded text-sm font-medium transition-colors ${
              showPuts ? "bg-purple-600 text-white" : "bg-gray-800 text-gray-400 border border-gray-600"
            }`}
          >
            Puts
          </button>
        </div>
        <div className="flex flex-wrap gap-2 items-center">
          {expirations.map(exp => {
            const date = new Date(Number(exp) * 1000);
            const dateStr = date.toLocaleDateString(undefined, { month: "short", day: "numeric" });
            return (
              <button
                key={exp}
                onClick={() => toggleExpiration(exp)}
                className={`px-3 py-1 rounded text-xs font-medium transition-colors ${
                  visibleExpirations.has(exp)
                    ? "bg-gray-600 text-white"
                    : "bg-gray-800 text-gray-400 border border-gray-600"
                }`}
              >
                {dateStr}
              </button>
            );
          })}
        </div>
      </div>

      <table className="w-full border-collapse text-sm">
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
          {strikes.map(strike => {
            const strikeFormatted = formatStrikeValue(BigInt(strike));

            return (
              <tr key={strike} className="border-b border-gray-800">
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
                <td className="p-2 text-center text-white font-medium bg-gray-900/50">${strikeFormatted}</td>

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
  // Bid = orange, Ask = blue. Both calls and puts use the same colour scheme.
  const colour = isBuy
    ? "text-blue-300 hover:text-blue-200"
    : "text-orange-300 hover:text-orange-200";
  const activeBox = isBuy
    ? "bg-blue-900/30 border border-blue-500"
    : "bg-orange-900/30 border border-orange-500";
  const title = `${isBuy ? "Buy" : "Sell"} ${opt.isPut ? "Put" : "Call"}`;
  return (
    <div className="flex-1 p-0.5">
      <button
        onClick={() => onSelect({ option: opt, isBuy })}
        title={title}
        className={`w-full px-1 py-1 rounded transition-colors text-xs tabular-nums ${colour} ${
          active ? activeBox : ""
        }`}
      >
        {price !== undefined ? price.toFixed(2) : "—"}
      </button>
    </div>
  );
}
