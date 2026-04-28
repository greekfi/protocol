"use client";

import { useEffect } from "react";
import { parseUnits } from "viem";
import { useAccount, useBalance, useChainId, useReadContract, useWaitForTransactionReceipt, useWriteContract } from "wagmi";
import { useReadFactoryApprovedOperator } from "~~/generated";
import deployedContracts from "~~/abi/deployedContracts";
import type { TradableOption } from "./useTradableOptions";

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
  {
    name: "decimals",
    type: "function",
    stateMutability: "view",
    inputs: [],
    outputs: [{ type: "uint8" }],
  },
] as const;

const BEBOP_ROUTER: Record<number, string> = {
  1: "0xbbbbbBB520d69a9775E85b458C58c648259FAD5F",
  8453: "0xbbbbbBB520d69a9775E85b458C58c648259FAD5F",
  42161: "0xbbbbbBB520d69a9775E85b458C58c648259FAD5F",
};

const USDC: Record<number, string> = {
  1: "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48",
  8453: "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913",
  42161: "0xaf88d065e77c8cC2239327C5EDb3A432268e5831",
};

const MAX_UINT = BigInt("0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff");

export type TradeDirection = "buy" | "sell";

export interface TradeApprovals {
  direction: TradeDirection;

  /** Parsed `amount` of OT in option-token wei. 0n when no input or no option. */
  optionAmountWei: bigint;
  optionDecimals: number;
  usdcDecimals: number;

  /** Wallet balances (used for the side-panel "Balances" display). */
  usdcBalance: bigint | undefined;
  optionBalance: bigint | undefined;

  /** Allowance state. */
  factoryOperatorApproved: boolean | undefined;
  /** Raw allowance values; useful for "done" flags on the always-visible Approvals card. */
  usdcAllowance: bigint | undefined;
  optionAllowance: bigint | undefined;

  needsUsdcApproval: boolean;
  handleApproveUsdc: () => void;

  needsOptionApproval: boolean;
  handleApproveOption: () => void;

  isApproving: boolean;
  /** True iff the approvals required for `direction` are satisfied. */
  allSatisfied: boolean;

  /** Refetch hooks; useful after a successful trade. */
  refetchAll: () => void;
}

interface UseTradeApprovalsArgs {
  option: TradableOption | null;
  amount: string;
  direction: TradeDirection;
  /** USDC-side amount that Bebop will pull on a Buy (string from quote.sellAmount). */
  usdcQuoteAmount?: string;
}

export function useTradeApprovals({
  option,
  amount,
  direction,
  usdcQuoteAmount,
}: UseTradeApprovalsArgs): TradeApprovals {
  const { address: userAddress } = useAccount();
  const chainId = useChainId();

  const bebopRouter = BEBOP_ROUTER[chainId];
  const optionToken = option?.optionAddress as `0x${string}` | undefined;
  const usdcAddress = (USDC[chainId] ?? USDC[1]) as `0x${string}`;
  const factoryAddress = deployedContracts[chainId as keyof typeof deployedContracts]?.Factory?.address as
    | `0x${string}`
    | undefined;

  const { data: optionDecimalsData } = useReadContract({
    address: optionToken,
    abi: ERC20_ABI,
    functionName: "decimals",
    query: { enabled: !!optionToken },
  });
  const optionDecimals = optionDecimalsData ?? 18;

  const { data: usdcDecimalsData } = useReadContract({
    address: usdcAddress,
    abi: ERC20_ABI,
    functionName: "decimals",
  });
  const usdcDecimals = usdcDecimalsData ?? 6;

  const optionAmountWei =
    option && amount && parseFloat(amount) > 0 ? parseUnits(amount, optionDecimals) : 0n;

  const { data: usdcBal, refetch: refetchUsdcBal } = useBalance({
    address: userAddress,
    token: usdcAddress,
    query: { enabled: !!userAddress },
  });
  const { data: optBal, refetch: refetchOptBal } = useBalance({
    address: userAddress,
    token: optionToken,
    query: { enabled: !!userAddress && !!optionToken },
  });

  const { data: usdcAllowance, refetch: refetchUsdcAllowance } = useReadContract({
    address: usdcAddress,
    abi: ERC20_ABI,
    functionName: "allowance",
    args: userAddress && bebopRouter ? [userAddress, bebopRouter as `0x${string}`] : undefined,
    query: { enabled: !!userAddress && !!bebopRouter },
  });

  const { data: optionAllowance, refetch: refetchOptionAllowance } = useReadContract({
    address: optionToken,
    abi: ERC20_ABI,
    functionName: "allowance",
    args: userAddress && bebopRouter ? [userAddress, bebopRouter as `0x${string}`] : undefined,
    query: { enabled: !!userAddress && !!bebopRouter && !!optionToken },
  });

  const { data: factoryOperatorApproved } = useReadFactoryApprovedOperator({
    address: factoryAddress,
    args: userAddress && bebopRouter ? [userAddress, bebopRouter as `0x${string}`] : undefined,
    query: { enabled: !!userAddress && !!bebopRouter && !!factoryAddress },
  });

  // Buy: need USDC allowance ≥ usdcQuoteAmount (the price Bebop is asking).
  const usdcNeeded = direction === "buy" && usdcQuoteAmount ? BigInt(usdcQuoteAmount) : 0n;
  const needsUsdcApproval =
    !!bebopRouter && usdcAllowance !== undefined && usdcNeeded > 0n && usdcAllowance < usdcNeeded;

  // Sell: need option allowance ≥ optionAmountWei OR factory-level operator approval.
  const needsOptionApproval =
    direction === "sell" &&
    !!bebopRouter &&
    !!optionToken &&
    optionAllowance !== undefined &&
    optionAmountWei > 0n &&
    optionAllowance < optionAmountWei &&
    !factoryOperatorApproved;

  const { writeContract: approve, data: approvalHash, isPending: isApproving } = useWriteContract();
  const { isSuccess: approvalConfirmed } = useWaitForTransactionReceipt({ hash: approvalHash });

  useEffect(() => {
    if (approvalConfirmed) {
      refetchUsdcAllowance();
      refetchOptionAllowance();
    }
  }, [approvalConfirmed, refetchUsdcAllowance, refetchOptionAllowance]);

  const handleApproveUsdc = () => {
    if (!bebopRouter) return;
    approve({
      address: usdcAddress,
      abi: ERC20_ABI,
      functionName: "approve",
      args: [bebopRouter as `0x${string}`, MAX_UINT],
    });
  };
  const handleApproveOption = () => {
    if (!bebopRouter || !optionToken) return;
    approve({
      address: optionToken,
      abi: ERC20_ABI,
      functionName: "approve",
      args: [bebopRouter as `0x${string}`, MAX_UINT],
    });
  };

  const refetchAll = () => {
    refetchUsdcAllowance();
    refetchOptionAllowance();
    refetchUsdcBal();
    refetchOptBal();
  };

  return {
    direction,
    optionAmountWei,
    optionDecimals,
    usdcDecimals,
    usdcBalance: usdcBal?.value,
    optionBalance: optBal?.value,
    factoryOperatorApproved,
    usdcAllowance: usdcAllowance as bigint | undefined,
    optionAllowance: optionAllowance as bigint | undefined,
    needsUsdcApproval,
    handleApproveUsdc,
    needsOptionApproval,
    handleApproveOption,
    isApproving,
    allSatisfied:
      direction === "buy" ? !needsUsdcApproval : !needsOptionApproval,
    refetchAll,
  };
}
