import type { OptionListItem } from "../hooks/types";
import { useMyOptionBalances } from "../hooks/useMyOptionBalances";
import { Address, formatUnits } from "viem";

interface MyOptionsProps {
  options: OptionListItem[];
  selected?: Address;
  onSelect: (address: Address) => void;
}

const shortLabel = (opt: OptionListItem): string => {
  // Option `name` is formatted like OPT-WETH-USDC-20250701-3000... by the contract.
  const parts = String(opt.name || "").split("-");
  if (parts.length < 4) {
    return `${opt.isPut ? "PUT" : "CALL"} ${opt.address.slice(0, 10)}…`;
  }
  const type = opt.isPut ? "PUT" : "CALL";
  const collateral = parts[1];
  const consideration = parts[2];
  const strike = opt.isPut ? BigInt(1e18) / opt.strike : opt.strike / BigInt(1e18);
  const iso = new Date(Number(opt.expiration) * 1000).toISOString().split("T")[0];
  return `${type} ${strike} ${collateral}/${consideration} ${iso}`;
};

const MyOptions = ({ options, selected, onSelect }: MyOptionsProps) => {
  const { held, isLoading, hasWallet } = useMyOptionBalances(options);

  return (
    <div className="p-6 bg-black/80 border border-gray-800 rounded-lg shadow-lg">
      <h2 className="text-xl font-light text-blue-300 mb-4">My Options</h2>

      {!hasWallet && <p className="text-gray-500 text-sm">Connect wallet to see your positions.</p>}

      {hasWallet && isLoading && <p className="text-gray-500 text-sm">Loading balances…</p>}

      {hasWallet && !isLoading && held.length === 0 && (
        <p className="text-gray-500 text-sm">You don&apos;t hold any option or redemption tokens.</p>
      )}

      {held.length > 0 && (
        <ul className="flex flex-col gap-1 max-h-64 overflow-y-auto pr-1">
          {held.map(opt => {
            const isSelected = selected?.toLowerCase() === opt.address.toLowerCase();
            return (
              <li key={opt.address}>
                <button
                  type="button"
                  onClick={() => onSelect(opt.address)}
                  className={`w-full text-left px-3 py-2 rounded border text-sm transition-colors ${
                    isSelected
                      ? "border-blue-400 bg-blue-500/20 text-blue-200"
                      : "border-gray-700 bg-black/60 text-blue-300 hover:border-blue-500 hover:bg-blue-500/10"
                  }`}
                  title={opt.address}
                >
                  <div className="truncate">{shortLabel(opt)}</div>
                  <div className="flex gap-3 text-xs text-gray-400 mt-0.5">
                    {opt.optionBalance > 0n && <span>long: {formatUnits(opt.optionBalance, 18)}</span>}
                    {opt.collBalance > 0n && <span>short: {formatUnits(opt.collBalance, 18)}</span>}
                  </div>
                </button>
              </li>
            );
          })}
        </ul>
      )}
    </div>
  );
};

export default MyOptions;
