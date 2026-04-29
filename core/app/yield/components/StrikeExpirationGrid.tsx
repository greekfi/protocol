import clsx from "clsx";
import { formatUnits } from "viem";
import type { TradableOption } from "../../trade/hooks/useTradableOptions";
import type { DirectPrice } from "../../trade/hooks/useDirectPrices";
import { displayStrike, formatStrikeValue } from "../../lib/strike";

interface StrikeExpirationGridProps {
  options: TradableOption[];
  loading: boolean;
  selectedAddress: string | null;
  onSelect: (opt: TradableOption) => void;
  prices?: Map<string, DirectPrice>;
}

const SECONDS_PER_YEAR = 365 * 24 * 60 * 60;

// Annualized yield for a covered-option writer. The MM's ask is quoted in USD per ETH-notional
// for BOTH calls and puts (see pricer.ts: "We return the USD/ETH BS price directly"). The
// writer doesn't actually earn the intrinsic — that's the forced sale/purchase offset on
// exercise — so real income is extrinsic (time value).
//
//   extrinsic = ask − intrinsic          (all per 1 ETH-notional, in USD)
//   yield_over_period = extrinsic / collateral-value
//   APR = yield_over_period × (year / time-to-expiry)
//
// Call: writer deposits 1 ETH worth `spot` USD. intrinsic = max(0, spot − strike).
//       yield = (ask − intrinsic) / spot
// Put : writer escrows `strike` USDC (enough to buy 1 ETH at strike). intrinsic = max(0, strike − spot).
//       yield = (ask − intrinsic) / strike
function formatApr(
  ask: number | undefined,
  spot: number | undefined,
  opt: TradableOption,
): string {
  if (ask === undefined || !Number.isFinite(ask) || ask <= 0) return "—";
  if (spot === undefined || !Number.isFinite(spot) || spot <= 0) return "—";
  const now = Math.floor(Date.now() / 1000);
  const secondsToExpiry = Number(opt.expiration) - now;
  if (secondsToExpiry <= 0) return "—";
  const strike = Number(formatUnits(displayStrike(opt), 18));
  if (!Number.isFinite(strike) || strike <= 0) return "—";

  const intrinsic = opt.isPut ? Math.max(0, strike - spot) : Math.max(0, spot - strike);
  const collateral = opt.isPut ? strike : spot;
  const yieldOverPeriod = (ask - intrinsic) / collateral;

  if (yieldOverPeriod <= 0) return "0%";
  const annualized = yieldOverPeriod * (SECONDS_PER_YEAR / secondsToExpiry) * 100;
  if (!Number.isFinite(annualized)) return "—";
  return `${Math.round(annualized)}%`;
}

function formatExpiry(expiration: bigint): string {
  const d = new Date(Number(expiration) * 1000);
  return d.toLocaleDateString(undefined, { month: "short", day: "numeric", year: "numeric", timeZone: "UTC" });
}

export function StrikeExpirationGrid({
  options,
  loading,
  selectedAddress,
  onSelect,
  prices,
}: StrikeExpirationGridProps) {
  if (loading) {
    return (
      <div className="mt-5 p-8 rounded-lg border border-dashed border-gray-700 bg-black/40 text-center text-gray-500 text-sm">
        Scanning for tradable options…
      </div>
    );
  }

  if (options.length === 0) {
    return (
      <div className="mt-5 p-8 rounded-lg border border-dashed border-gray-700 bg-black/40 text-center text-gray-500 text-sm">
        No active options found for this pair on the current chain.
      </div>
    );
  }

  // Index by display-strike (bigint) so calls and puts with equivalent strikes land in the same column.
  const strikesByValue = new Map<string, bigint>();
  const byCell = new Map<string, TradableOption>();
  const expirationSet = new Set<string>();

  for (const o of options) {
    const dispStrike = displayStrike(o);
    strikesByValue.set(dispStrike.toString(), dispStrike);
    expirationSet.add(o.expiration.toString());
    byCell.set(`${dispStrike}|${o.expiration}`, o);
  }

  const strikes = Array.from(strikesByValue.values()).sort((a, b) => (a < b ? -1 : a > b ? 1 : 0));
  const expirations = Array.from(expirationSet)
    .map(s => BigInt(s))
    .sort((a, b) => (a < b ? -1 : a > b ? 1 : 0));

  return (
    <div className="mt-5 w-full overflow-x-auto rounded-lg border border-gray-800 bg-black/40">
      <table className="w-auto min-w-full border-collapse text-sm">
        <thead>
          <tr>
            <th className="sticky left-0 z-10 bg-black/80 pl-3 pr-6 py-2 text-left text-xs uppercase tracking-wider text-gray-400 border-b border-gray-800 whitespace-nowrap">
              ↓ Expiry / → Strike
            </th>
            {strikes.map((s, i) => (
              <th
                key={s.toString()}
                className={clsx(
                  "px-3 py-2 text-right text-sm font-semibold text-blue-100 border-b border-gray-800 tabular-nums",
                  i === 0 && "pl-6",
                )}
              >
                {formatStrikeValue(s)}
              </th>
            ))}
          </tr>
        </thead>
        <tbody>
          {expirations.map(exp => (
            <tr key={exp.toString()} className="hover:bg-blue-500/5">
              <th className="sticky left-0 z-10 bg-black/80 pl-3 pr-6 py-2 text-left text-sm font-semibold text-blue-100 border-b border-gray-800 whitespace-nowrap">
                {formatExpiry(exp)}
              </th>
              {strikes.map((s, i) => {
                const opt = byCell.get(`${s}|${exp}`);
                const isSelected = opt && opt.optionAddress === selectedAddress;
                const price = opt ? prices?.get(opt.optionAddress.toLowerCase()) : undefined;
                const ask = price?.ask;
                const spot = price?.spotPrice;
                const display = opt ? formatApr(ask, spot, opt) : "—";
                return (
                  <td
                    key={s.toString()}
                    className={clsx(
                      "border-b border-gray-900 p-1 text-right tabular-nums",
                      i === 0 && "pl-6",
                    )}
                  >
                    {opt ? (
                      <button
                        type="button"
                        onClick={() => onSelect(opt)}
                        className={clsx(
                          "w-full px-3 py-2 rounded-md transition-colors",
                          isSelected
                            ? "bg-[#2F50FF]/25 text-[#35F3FF] font-semibold ring-2 ring-inset ring-[#2F50FF]"
                            : display !== "—"
                              ? "text-emerald-300 hover:bg-[#2F50FF]/10 hover:text-[#35F3FF]"
                              : "text-gray-500 hover:bg-gray-500/10",
                        )}
                        title={
                          ask !== undefined
                            ? `ask ${ask?.toFixed(4)} · spot ${spot?.toFixed(2) ?? "?"} · ${opt.optionAddress}`
                            : opt.optionAddress
                        }
                      >
                        {display}
                      </button>
                    ) : (
                      <span className="block px-3 py-2 text-gray-700">—</span>
                    )}
                  </td>
                );
              })}
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}
