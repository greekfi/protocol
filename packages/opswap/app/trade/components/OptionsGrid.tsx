import { useMemo } from "react";
import { useTradableOptions, type TradableOption } from "../hooks/useTradableOptions";
import { formatUnits } from "viem";
import { usePricingStream } from "../../hooks/usePricingStream";

interface OptionsGridProps {
  selectedToken: string;
  onSelectOption: (option: TradableOption) => void;
}

interface GridCell {
  call?: TradableOption;
  put?: TradableOption;
}

export function OptionsGrid({ selectedToken, onSelectOption }: OptionsGridProps) {
  const { data: options, isLoading } = useTradableOptions(selectedToken);

  // Connect to pricing stream only when we have options
  const { getPrice, isConnected } = usePricingStream({
    enabled: !!options && options.length > 0,
  });

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
      // Put strike is stored as "USDC per WETH", we want "WETH per USDC"
      let normalizedStrike = option.strike;
      if (option.isPut && option.strike > 0n) {
        // Invert: 1 / strike (with 18 decimal precision)
        normalizedStrike = (10n ** 36n) / option.strike;
      }

      // Round strike to 2 decimal places to group similar strikes together
      // Convert to float, round, then back to BigInt with 18 decimals
      const strikeFloat = parseFloat(formatUnits(normalizedStrike, 18));
      const strikeRounded = Math.round(strikeFloat * 100) / 100; // Round to 2 decimals
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

    // Sort strikes and expirations
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
      <h2 className="text-xl font-light text-blue-300 mb-4">Options Chain</h2>
      <div className="text-sm text-gray-400 mb-4">
        Click on a price to trade. {isConnected ? "🟢 Live prices" : "⚪ Connecting..."}
      </div>

      <table className="w-full border-collapse text-sm">
        <thead>
          <tr className="border-b border-gray-700">
            <th className="p-2 text-left text-gray-400">Strike</th>
            {expirations.map(exp => {
              const date = new Date(Number(exp) * 1000);
              return (
                <th key={exp} className="p-2 text-center text-gray-400">
                  {date.toLocaleDateString()}
                  <br />
                  <span className="text-xs text-gray-500">{date.toLocaleTimeString()}</span>
                </th>
              );
            })}
          </tr>
        </thead>
        <tbody>
          {strikes.map(strike => {
            // Format strike price (it's encoded with 18 decimals)
            const strikeNum = parseFloat(formatUnits(BigInt(strike), 18));
            // Round to 2 decimal places for cleaner display
            const strikeFormatted = strikeNum.toFixed(2);

            return (
              <tr key={strike} className="border-b border-gray-800">
                <td className="p-2 text-blue-300 font-medium">${strikeFormatted}</td>
                {expirations.map(exp => {
                  const key = `${strike}-${exp}`;
                  const cell = grid.get(key);

                  return (
                    <td key={exp} className="p-2 text-center">
                      {cell ? (
                        <div className="space-y-1">
                          {cell.call && (
                            <PriceCell option={cell.call} label="C" onSelect={onSelectOption} getPrice={getPrice} />
                          )}
                          {cell.put && (
                            <PriceCell option={cell.put} label="P" onSelect={onSelectOption} getPrice={getPrice} />
                          )}
                        </div>
                      ) : (
                        <span className="text-gray-600">-</span>
                      )}
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

interface PriceCellProps {
  option: TradableOption;
  label: string;
  onSelect: (option: TradableOption) => void;
  getPrice: (tokenAddress: string) => { bids: [number, number][]; asks: [number, number][] } | undefined;
}

function PriceCell({ option, label, onSelect, getPrice }: PriceCellProps) {
  // Get option price using the option token address
  const priceData = getPrice(option.optionAddress);

  // Show best bid/ask from the spot price
  const bestBid = priceData?.bids[0]?.[0];
  const bestAsk = priceData?.asks[0]?.[0];

  const priceDisplay = bestBid && bestAsk
    ? `${bestBid.toFixed(2)}/${bestAsk.toFixed(2)}`
    : "—";

  return (
    <button
      onClick={() => onSelect(option)}
      className="px-2 py-1 rounded bg-gray-900 hover:bg-blue-900 border border-gray-700 hover:border-blue-500 text-blue-300 transition-colors text-xs"
      title={`Spot: ${priceDisplay}`}
    >
      {label}: {priceDisplay}
    </button>
  );
}
