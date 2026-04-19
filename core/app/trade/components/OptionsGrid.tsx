import { useEffect, useMemo, useState } from "react";
import { usePricing } from "../../contexts/PricingContext";
import { type TradableOption, useTradableOptions } from "../hooks/useTradableOptions";
import { formatUnits } from "viem";

export interface OptionSelection {
  option: TradableOption;
  isBuy: boolean; // true = buying option (user pays USDC), false = selling option (user receives USDC)
}

interface OptionsGridProps {
  selectedToken: string;
  onSelectOption: (selection: OptionSelection) => void;
}

interface GridCell {
  call?: TradableOption;
  put?: TradableOption;
}

export function OptionsGrid({ selectedToken, onSelectOption }: OptionsGridProps) {
  const [showCalls, setShowCalls] = useState(true);
  const [showPuts, setShowPuts] = useState(true);
  const [visibleExpirations, setVisibleExpirations] = useState<Set<string>>(new Set());

  const { data: options, isLoading } = useTradableOptions(selectedToken);

  // Use pricing from context (connection is managed at layout level)
  const { getPrice, isConnected } = usePricing();

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
    return (
      <div className="p-6 bg-black/80 border border-gray-800 rounded-lg shadow-lg">
        <div className="text-blue-300">Loading options...</div>
      </div>
    );
  }

  if (!options || options.length === 0) {
    return (
      <div className="p-6 bg-black/80 border border-gray-800 rounded-lg shadow-lg">
        <div className="text-gray-400">No options available for this token</div>
      </div>
    );
  }

  return (
    <div className="p-6 bg-black/80 border border-gray-800 rounded-lg shadow-lg overflow-x-auto">
      <div className="flex justify-between items-center mb-4">
        <h2 className="text-xl font-light text-blue-300">Options Chain</h2>
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
      </div>

      {/* Expiration date toggles */}
      <div className="flex flex-wrap gap-2 mb-4">
        <span className="text-gray-500 text-sm py-1">Expirations:</span>
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

      <div className="text-sm text-gray-400 mb-4">
        Click on a price to trade. {isConnected ? "🟢 Live prices" : "⚪ Connecting..."}
      </div>

      {/* Legend */}
      <div className="flex gap-4 mb-4 text-xs text-gray-500">
        <div className="flex items-center gap-1">
          <div className="w-3 h-3 bg-orange-900/50 border border-orange-700 rounded"></div>
          <span>Call Bid</span>
        </div>
        <div className="flex items-center gap-1">
          <div className="w-3 h-3 bg-blue-900/50 border border-blue-700 rounded"></div>
          <span>Call Ask</span>
        </div>
        <div className="flex items-center gap-1">
          <div className="w-3 h-3 bg-yellow-900/50 border border-yellow-700 rounded"></div>
          <span>Put Bid</span>
        </div>
        <div className="flex items-center gap-1">
          <div className="w-3 h-3 bg-purple-900/50 border border-purple-700 rounded"></div>
          <span>Put Ask</span>
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
                      <span className="flex-1 text-yellow-400">Bid</span>
                      <span className="flex-1 text-purple-400">Ask</span>
                    </div>
                  </th>
                );
              })}
          </tr>
        </thead>
        <tbody>
          {strikes.map(strike => {
            const strikeNum = parseFloat(formatUnits(BigInt(strike), 18));
            const strikeFormatted = strikeNum.toFixed(2);

            return (
              <tr key={strike} className="border-b border-gray-800">
                {/* Call columns for each expiration */}
                {showCalls &&
                  filteredExpirations.map(exp => {
                    const key = `${strike}-${exp}`;
                    const cell = grid.get(key);
                    const callPrice = cell?.call ? getPrice(cell.call.optionAddress) : undefined;
                    const callBid = callPrice?.bids[0]?.[0];
                    const callAsk = callPrice?.asks[0]?.[0];

                    return (
                      <td key={`call-${exp}`} colSpan={2} className="p-0 border-r border-gray-800">
                        <div className="flex">
                          {/* Call Bid */}
                          <div className="flex-1 p-0.5">
                            {cell?.call ? (
                              <button
                                onClick={() => onSelectOption({ option: cell.call!, isBuy: false })}
                                className="w-full px-1 py-1 rounded bg-orange-900/30 hover:bg-orange-800/50 border border-orange-700/50 hover:border-orange-500 text-orange-300 transition-colors text-xs"
                                title="Sell Call"
                              >
                                {callBid !== undefined ? callBid.toFixed(2) : "—"}
                              </button>
                            ) : (
                              <span className="block text-center text-gray-700 text-xs py-1">—</span>
                            )}
                          </div>
                          {/* Call Ask */}
                          <div className="flex-1 p-0.5">
                            {cell?.call ? (
                              <button
                                onClick={() => onSelectOption({ option: cell.call!, isBuy: true })}
                                className="w-full px-1 py-1 rounded bg-blue-900/30 hover:bg-blue-800/50 border border-blue-700/50 hover:border-blue-500 text-blue-300 transition-colors text-xs"
                                title="Buy Call"
                              >
                                {callAsk !== undefined ? callAsk.toFixed(2) : "—"}
                              </button>
                            ) : (
                              <span className="block text-center text-gray-700 text-xs py-1">—</span>
                            )}
                          </div>
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
                    const putBid = putPrice?.bids[0]?.[0];
                    const putAsk = putPrice?.asks[0]?.[0];

                    return (
                      <td key={`put-${exp}`} colSpan={2} className="p-0 border-l border-gray-800">
                        <div className="flex">
                          {/* Put Bid */}
                          <div className="flex-1 p-0.5">
                            {cell?.put ? (
                              <button
                                onClick={() => onSelectOption({ option: cell.put!, isBuy: false })}
                                className="w-full px-1 py-1 rounded bg-yellow-900/30 hover:bg-yellow-800/50 border border-yellow-700/50 hover:border-yellow-500 text-yellow-300 transition-colors text-xs"
                                title="Sell Put"
                              >
                                {putBid !== undefined ? putBid.toFixed(2) : "—"}
                              </button>
                            ) : (
                              <span className="block text-center text-gray-700 text-xs py-1">—</span>
                            )}
                          </div>
                          {/* Put Ask */}
                          <div className="flex-1 p-0.5">
                            {cell?.put ? (
                              <button
                                onClick={() => onSelectOption({ option: cell.put!, isBuy: true })}
                                className="w-full px-1 py-1 rounded bg-purple-900/30 hover:bg-purple-800/50 border border-purple-700/50 hover:border-purple-500 text-purple-300 transition-colors text-xs"
                                title="Buy Put"
                              >
                                {putAsk !== undefined ? putAsk.toFixed(2) : "—"}
                              </button>
                            ) : (
                              <span className="block text-center text-gray-700 text-xs py-1">—</span>
                            )}
                          </div>
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
