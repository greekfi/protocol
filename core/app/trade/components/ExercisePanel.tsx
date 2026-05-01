"use client";

import { useState } from "react";
import { formatUnits, parseUnits } from "viem";
import { useAccount, useBalance, useWaitForTransactionReceipt } from "wagmi";
import {
  useReadOptionReceipt,
  useReadReceiptToNeededConsideration,
  useWriteOptionExercise,
} from "~~/generated";

interface ExercisePanelProps {
  optionAddress: string;
  considerationAddress: string;
  optionDecimals: number;
  consDecimals: number;
  consSymbol: string;
}

export function ExercisePanel({
  optionAddress,
  considerationAddress,
  optionDecimals,
  consDecimals,
  consSymbol,
}: ExercisePanelProps) {
  const { address: userAddress } = useAccount();
  const [amount, setAmount] = useState("1");
  const amountWei = amount && parseFloat(amount) > 0 ? parseUnits(amount, optionDecimals) : 0n;

  const { data: receiptAddress } = useReadOptionReceipt({
    address: optionAddress as `0x${string}`,
  });

  const { data: needed } = useReadReceiptToNeededConsideration({
    address: receiptAddress,
    args: amountWei > 0n ? [amountWei] : undefined,
    query: { enabled: !!receiptAddress && amountWei > 0n },
  });

  const { data: consBalance } = useBalance({
    address: userAddress,
    token: considerationAddress as `0x${string}`,
    query: { enabled: !!userAddress },
  });

  const hasEnough = needed !== undefined && consBalance !== undefined && consBalance.value >= needed;

  const { writeContract: exercise, data: txHash, isPending } = useWriteOptionExercise();
  const { isSuccess } = useWaitForTransactionReceipt({ hash: txHash });

  const handleExercise = () => {
    if (amountWei === 0n) return;
    exercise({ address: optionAddress as `0x${string}`, args: [amountWei] });
  };

  const neededDisplay =
    needed !== undefined ? Number(formatUnits(needed, consDecimals)).toLocaleString(undefined, { maximumFractionDigits: 4 }) : "—";

  return (
    <div className="rounded-xl border border-emerald-500/30 bg-gradient-to-b from-emerald-500/5 to-black/60 px-4 py-3 min-w-[16rem] max-w-[20rem] flex-1">
      <div className="text-xs uppercase tracking-wider text-gray-400 font-semibold mb-2">Exercise</div>
      <div className="flex items-center gap-2">
        <div className="flex items-center rounded-lg border border-gray-800 bg-black/50 focus-within:border-emerald-400 flex-1 min-w-0">
          <input
            type="text"
            inputMode="decimal"
            maxLength={8}
            value={amount}
            onChange={e => {
              const v = e.target.value;
              if (/^\d*\.?\d*$/.test(v) && v.length <= 8) setAmount(v);
            }}
            placeholder="0"
            className="w-full px-3 py-2 bg-transparent text-emerald-100 text-base outline-none tabular-nums"
          />
          <span className="pr-3 text-xs text-gray-500 uppercase tracking-wider">option</span>
        </div>
        <button
          type="button"
          onClick={handleExercise}
          disabled={isPending || amountWei === 0n}
          className="px-3 py-1.5 rounded-lg text-white text-sm font-semibold bg-emerald-500 hover:bg-emerald-400 disabled:opacity-50"
        >
          {isPending ? "…" : isSuccess ? "Exercised ✓" : "Exercise"}
        </button>
      </div>
      <div className="mt-2 text-sm flex items-center gap-2">
        <span className="text-gray-400">Need</span>
        <span className="tabular-nums text-white">
          {neededDisplay} {consSymbol}
        </span>
        <span className={hasEnough ? "text-emerald-400" : "text-red-400"}>{hasEnough ? "✓" : "✗"}</span>
      </div>
    </div>
  );
}
