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
  useReadOptionExerciseDeadline,
  useReadOptionExpirationDate,
  useReadOptionIsEuro,
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

  const { data: optionBalance } = useBalance({
    address: userAddress,
    token: optionAddress as `0x${string}`,
    query: { enabled: !!userAddress },
  });

  const maxStr = optionBalance ? formatUnits(optionBalance.value, optionDecimals) : "0";
  const [amount, setAmount] = useState<string>("");

  // Default the input to the user's full option balance once it's loaded.
  // Keep tracking the max as long as the user hasn't typed something else.
  const [touched, setTouched] = useState(false);
  useEffect(() => {
    if (!touched) setAmount(maxStr);
  }, [maxStr, touched]);

  const parsedWei = amount && parseFloat(amount) > 0 ? parseUnits(amount, optionDecimals) : 0n;
  const maxWei = optionBalance?.value ?? 0n;
  const amountWei = parsedWei > maxWei ? maxWei : parsedWei;

  const { data: receiptAddress } = useReadOptionReceipt({
    address: optionAddress as `0x${string}`,
  });
  const { data: isEuro } = useReadOptionIsEuro({ address: optionAddress as `0x${string}` });
  const { data: expirationDate } = useReadOptionExpirationDate({ address: optionAddress as `0x${string}` });
  const { data: exerciseDeadline } = useReadOptionExerciseDeadline({ address: optionAddress as `0x${string}` });

  const now = BigInt(Math.floor(Date.now() / 1000));
  const preExpiry = expirationDate !== undefined && now < BigInt(expirationDate);
  const euroBlocked = isEuro === true && preExpiry;
  const windowHours =
    expirationDate !== undefined && exerciseDeadline !== undefined
      ? Number((BigInt(exerciseDeadline) - BigInt(expirationDate)) / 3600n)
      : undefined;

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
    <div className="rounded-xl border border-emerald-500/30 bg-gradient-to-b from-emerald-500/5 to-black/60 px-4 py-3 w-[14rem]">
      <div className="text-xs uppercase tracking-wider text-gray-400 font-semibold mb-2">Exercise</div>
      <div className="flex flex-col gap-2">
        <div className="flex items-center rounded-lg border border-gray-800 bg-black/50 focus-within:border-emerald-400 min-w-0">
          <input
            type="text"
            inputMode="decimal"
            maxLength={20}
            value={amount}
            onChange={e => {
              const v = e.target.value;
              if (!/^\d*\.?\d*$/.test(v)) return;
              setTouched(true);
              // Clamp typed input to the user's option balance.
              if (v && parseFloat(v) > 0 && maxWei > 0n) {
                const wei = parseUnits(v, optionDecimals);
                if (wei > maxWei) {
                  setAmount(maxStr);
                  return;
                }
              }
              setAmount(v);
            }}
            placeholder="0"
            className="w-full px-3 py-2 bg-transparent text-emerald-100 text-base outline-none tabular-nums"
          />
          <button
            type="button"
            onClick={() => {
              setTouched(true);
              setAmount(maxStr);
            }}
            disabled={maxWei === 0n}
            className="px-1.5 text-[10px] uppercase tracking-wider text-emerald-400 hover:text-emerald-300 disabled:opacity-30"
          >
            max
          </button>
          <span className="pr-3 text-xs text-gray-500 uppercase tracking-wider">OPT</span>
        </div>
        <button
          type="button"
          onClick={handleExercise}
          disabled={isPending || amountWei === 0n || !approvalsDone || euroBlocked}
          title={
            euroBlocked
              ? "European option — only exercisable after expiration"
              : !approvalsDone
                ? `Approve ${consSymbol} first`
                : undefined
          }
          className="w-full px-3 py-1.5 rounded-lg text-white text-sm font-semibold bg-emerald-500 hover:bg-emerald-400 disabled:opacity-50"
        >
          {isPending ? "…" : isSuccess ? "Exercised ✓" : "Exercise"}
        </button>
      </div>
      {euroBlocked && (
        <div className="mt-2 text-[11px] text-amber-300/80">
          Euro options exercisable only after expiration{windowHours ? ` for ${windowHours}h` : ""}.
        </div>
      )}
      <div className="mt-2 text-sm flex items-center gap-2">
        <span className="text-gray-400">Balance</span>
        <span className="tabular-nums text-white">
          {Number(maxStr).toLocaleString(undefined, { maximumFractionDigits: 4 })}
        </span>
      </div>
      <div className="mt-1 text-sm flex items-center gap-2">
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
