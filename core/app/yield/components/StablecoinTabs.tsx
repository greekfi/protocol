import clsx from "clsx";
import Image from "next/image";
import { useState } from "react";
import { STABLECOINS, type Stablecoin } from "../data";

interface StablecoinTabsProps {
  selected: string;
  onSelect: (symbol: string) => void;
}

function Badge({ coin }: { coin: Stablecoin }) {
  const [errored, setErrored] = useState(false);
  if (errored) {
    return (
      <span
        className={clsx(
          "inline-flex items-center justify-center w-6 h-6 rounded-full text-[10px] font-semibold text-white",
          coin.color,
        )}
      >
        {coin.symbol[0]}
      </span>
    );
  }
  return (
    <Image
      src={`/tokens/${coin.symbol.toLowerCase()}.png`}
      alt={coin.symbol}
      width={22}
      height={22}
      className="rounded-full"
      onError={() => setErrored(true)}
    />
  );
}

export function StablecoinTabs({ selected, onSelect }: StablecoinTabsProps) {
  return (
    <div className="flex flex-wrap gap-2">
      {STABLECOINS.map(coin => {
        const active = coin.symbol === selected;
        return (
          <button
            key={coin.symbol}
            type="button"
            onClick={() => onSelect(coin.symbol)}
            className={clsx(
              "flex items-center gap-2 px-4 py-2 rounded-lg border text-sm font-medium transition-colors",
              active
                ? "bg-[#2F50FF]/15 border-[#2F50FF] text-[#35F3FF]"
                : "bg-black/40 border-gray-800 text-gray-400 hover:text-[#35F3FF] hover:border-[#2F50FF]/60",
            )}
          >
            <Badge coin={coin} />
            {coin.symbol}
          </button>
        );
      })}
    </div>
  );
}
