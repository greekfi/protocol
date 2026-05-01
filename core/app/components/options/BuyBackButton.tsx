import { formatUnits } from "viem";
import { useAccount, useChainId, useReadContract } from "wagmi";
import { useBebopQuote } from "../../trade/hooks/useBebopQuote";
import { useBebopTrade } from "../../trade/hooks/useBebopTrade";
import { usdcFor } from "../../data/chains";

const ERC20_ABI = [
  {
    name: "decimals",
    type: "function",
    stateMutability: "view",
    inputs: [],
    outputs: [{ type: "uint8" }],
  },
] as const;

function fmtUsd(n: number | undefined): string {
  if (n === undefined || !Number.isFinite(n)) return "—";
  if (n >= 1) return `$${n.toLocaleString(undefined, { maximumFractionDigits: 2 })}`;
  if (n >= 0.01) return `$${n.toFixed(3)}`;
  return `$${n.toPrecision(2)}`;
}

interface BuyBackRowProps {
  optionAddress: `0x${string}`;
  shortAmount: bigint;
}

/**
 * Bottom row of the boxed Short balance. Renders `cost $X` on the left and
 * the Buy-Back button on the right. Fetches its own buy-side quote
 * (buyToken=option, sellToken=USDC, buyAmount=short).
 */
export function BuyBackRow({ optionAddress, shortAmount }: BuyBackRowProps) {
  const { address: userAddress } = useAccount();
  const chainId = useChainId();
  const paymentToken = usdcFor(chainId) ?? usdcFor(1)!;

  const { data: usdcDecimalsData } = useReadContract({
    address: paymentToken as `0x${string}`,
    abi: ERC20_ABI,
    functionName: "decimals",
  });
  const usdcDecimals = usdcDecimalsData ?? 6;

  const enabled = !!userAddress && shortAmount > 0n;

  const { data: quote, isLoading } = useBebopQuote({
    buyToken: optionAddress,
    sellToken: paymentToken,
    buyAmount: enabled ? shortAmount.toString() : undefined,
    enabled,
  });

  const { executeTrade, status } = useBebopTrade();
  const isBuying = status === "preparing" || status === "pending";

  const cost =
    quote?.sellAmount ? Number(formatUnits(BigInt(quote.sellAmount), usdcDecimals)) : undefined;

  const handleBuyBack = async () => {
    if (!quote) return;
    try {
      await executeTrade(quote);
    } catch (e) {
      console.error("[yield] buy-back failed", e);
    }
  };

  return (
    <div className="flex items-center justify-between gap-3 text-xs">
      <span className="text-gray-500">
        cost{" "}
        <span className="text-white tabular-nums">
          {isLoading ? "…" : fmtUsd(cost)}
        </span>
      </span>
      <button
        type="button"
        onClick={handleBuyBack}
        disabled={!quote || isBuying || shortAmount === 0n}
        className="px-2 py-1 rounded-md bg-[#2F50FF] hover:bg-[#35F3FF] hover:text-black text-white text-[11px] font-semibold disabled:opacity-50 transition-colors"
        title={shortAmount === 0n ? "No short position to close" : "Buy back option tokens to close the short"}
      >
        {isBuying ? "Buying…" : status === "success" ? "Closed ✓" : "Buy Back"}
      </button>
    </div>
  );
}
