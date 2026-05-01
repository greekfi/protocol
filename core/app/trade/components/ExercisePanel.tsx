"use client";

import { useEffect, useState } from "react";
import { formatUnits, parseUnits } from "viem";
import {
  useAccount,
  useBalance,
  useChainId,
  useReadContract,
  useWaitForTransactionReceipt,
  useWriteContract,
} from "wagmi";
import {
  factoryAbi,
  useReadOptionReceipt,
  useReadReceiptToNeededConsideration,
  useWriteFactoryApprove,
  useWriteOptionExercise,
} from "~~/generated";
import deployedContracts from "~~/abi/deployedContracts";

const ERC20_ABI = [
  {
    name: "approve",
    type: "function",
    stateMutability: "nonpayable",
    inputs: [
      { name: "spender", type: "address" },
      { name: "amount", type: "uint256" },
    ],
    outputs: [{ type: "bool" }],
  },
  {
    name: "allowance",
    type: "function",
    stateMutability: "view",
    inputs: [
      { name: "owner", type: "address" },
      { name: "spender", type: "address" },
    ],
    outputs: [{ type: "uint256" }],
  },
] as const;

const MAX_UINT = BigInt("0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff");

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
  const chainId = useChainId();
  const factoryAddress = deployedContracts[chainId as keyof typeof deployedContracts]?.Factory?.address as
    | `0x${string}`
    | undefined;

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

  // Two-layer consideration approval mirrors the collateral pattern in
  // useTradeApprovals: ERC20.approve(factory) + factory.approve(token).
  const { data: erc20Allowance, refetch: refetchErc20 } = useReadContract({
    address: considerationAddress as `0x${string}`,
    abi: ERC20_ABI,
    functionName: "allowance",
    args: userAddress && factoryAddress ? [userAddress, factoryAddress] : undefined,
    query: { enabled: !!userAddress && !!factoryAddress },
  });
  const { data: factoryAllowance, refetch: refetchFactory } = useReadContract({
    address: factoryAddress,
    abi: factoryAbi,
    functionName: "allowance",
    args: userAddress ? [considerationAddress as `0x${string}`, userAddress] : undefined,
    query: { enabled: !!userAddress && !!factoryAddress },
  });

  const erc20Done = (erc20Allowance ?? 0n) > 0n;
  const factoryDone = (factoryAllowance ?? 0n) > 0n;
  const approvalsDone = erc20Done && factoryDone;
  const approvalsHalf = !approvalsDone && (erc20Done || factoryDone);

  const {
    writeContract: erc20Approve,
    data: erc20Hash,
    isPending: isErc20Approving,
  } = useWriteContract();
  const { isSuccess: erc20Confirmed } = useWaitForTransactionReceipt({ hash: erc20Hash });
  useEffect(() => {
    if (erc20Confirmed) refetchErc20();
  }, [erc20Confirmed, refetchErc20]);

  const {
    writeContract: factoryApprove,
    data: factoryHash,
    isPending: isFactoryApproving,
  } = useWriteFactoryApprove();
  const { isSuccess: factoryConfirmed } = useWaitForTransactionReceipt({ hash: factoryHash });
  useEffect(() => {
    if (factoryConfirmed) refetchFactory();
  }, [factoryConfirmed, refetchFactory]);

  const handleApprove = () => {
    if (!factoryAddress) return;
    if (!erc20Done) {
      erc20Approve({
        address: considerationAddress as `0x${string}`,
        abi: ERC20_ABI,
        functionName: "approve",
        args: [factoryAddress, MAX_UINT],
      });
      return;
    }
    if (!factoryDone) {
      factoryApprove({ address: factoryAddress, args: [considerationAddress as `0x${string}`, MAX_UINT] });
    }
  };

  const isApproving = isErc20Approving || isFactoryApproving;

  const { writeContract: exercise, data: txHash, isPending } = useWriteOptionExercise();
  const { isSuccess } = useWaitForTransactionReceipt({ hash: txHash });

  const handleExercise = () => {
    if (amountWei === 0n) return;
    exercise({ address: optionAddress as `0x${string}`, args: [amountWei] });
  };

  const neededDisplay =
    needed !== undefined
      ? Number(formatUnits(needed, consDecimals)).toLocaleString(undefined, { maximumFractionDigits: 4 })
      : "—";

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
          disabled={isPending || amountWei === 0n || !approvalsDone}
          title={!approvalsDone ? `Approve ${consSymbol} first` : undefined}
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
      <div className="mt-2 text-sm flex items-center gap-2">
        <span className="text-gray-400">Approve {consSymbol}</span>
        {approvalsDone ? (
          <span className="text-emerald-400">✓</span>
        ) : (
          <button
            type="button"
            onClick={handleApprove}
            disabled={isApproving}
            className={`px-2 py-0.5 rounded-md text-xs font-semibold text-black disabled:opacity-50 ${
              approvalsHalf ? "bg-pink-500 hover:bg-pink-400" : "bg-[#FF8300] hover:bg-[#e07400]"
            }`}
          >
            {isApproving ? "…" : "Approve"}
          </button>
        )}
      </div>
    </div>
  );
}
