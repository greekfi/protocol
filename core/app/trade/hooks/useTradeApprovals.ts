"use client";

import { useEffect } from "react";
import { parseUnits } from "viem";
import { useAccount, useBalance, useChainId, useReadContract, useWaitForTransactionReceipt, useWriteContract } from "wagmi";
import {
  factoryAbi,
  useReadFactoryApprovedOperator,
  useReadFactoryAutoMintBurn,
  useWriteFactoryApprove,
  useWriteFactoryApproveOperator,
  useWriteFactoryEnableAutoMintBurn,
} from "~~/generated";
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

import { bebopRouterFor, usdcFor } from "../../data/chains";

const MAX_UINT = BigInt("0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff");

export type TradeDirection = "buy" | "sell";

export interface TradeApprovals {
  direction: TradeDirection;

  /** Parsed `amount` of OT in option-token wei. 0n when no input or no option. */
  optionAmountWei: bigint;
  optionDecimals: number;
  usdcDecimals: number;

  /** Symbol of the option's collateral token, for labelling the approval row. */
  collateralSymbol: string;

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

  /** Auto-mint toggle. When enabled, the Option contract auto-mints from
   *  collateral on transfer when the sender's balance is short — required
   *  for selling options on Bebop without a manual mint step. */
  autoMintEnabled: boolean | undefined;
  needsAutoMint: boolean;
  handleEnableAutoMint: () => void;

  /** Collateral → Factory approval (two layers: ERC20.approve(factory) and
   *  factory.approve(token)). One click fires the next missing layer; two
   *  clicks total to fully approve. */
  collateralErc20Allowance: bigint | undefined;
  collateralFactoryAllowance: bigint | undefined;
  needsCollateralApproval: boolean;
  handleApproveCollateral: () => void;

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
  /** Symbol of the collateral token, for labelling. Optional — falls back
   *  to the address suffix if not supplied. */
  collateralSymbol?: string;
}

export function useTradeApprovals({
  option,
  amount,
  direction,
  usdcQuoteAmount,
  collateralSymbol,
}: UseTradeApprovalsArgs): TradeApprovals {
  const { address: userAddress } = useAccount();
  const chainId = useChainId();

  const bebopRouter = bebopRouterFor(chainId);
  const optionToken = option?.optionAddress as `0x${string}` | undefined;
  const collateralAddress = option?.collateralAddress as `0x${string}` | undefined;
  const usdcAddress = (usdcFor(chainId) ?? usdcFor(1)) as `0x${string}`;
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

  const { data: factoryOperatorApproved, refetch: refetchFactoryOperator } = useReadFactoryApprovedOperator({
    address: factoryAddress,
    args: userAddress && bebopRouter ? [userAddress, bebopRouter as `0x${string}`] : undefined,
    query: { enabled: !!userAddress && !!bebopRouter && !!factoryAddress },
  });

  // Auto-mint flag — required for selling options the user doesn't yet hold:
  // Option transfers auto-mint from collateral when this is on.
  const { data: autoMintEnabled, refetch: refetchAutoMint } = useReadFactoryAutoMintBurn({
    address: factoryAddress,
    args: userAddress ? [userAddress] : undefined,
    query: { enabled: !!userAddress && !!factoryAddress },
  });

  // Collateral approvals — both layers (ERC20.approve(factory) + factory.approve(token))
  // are required for the factory's two-layer pull on auto-mint.
  const { data: collateralErc20Allowance, refetch: refetchCollateralErc20 } = useReadContract({
    address: collateralAddress,
    abi: ERC20_ABI,
    functionName: "allowance",
    args: userAddress && factoryAddress ? [userAddress, factoryAddress] : undefined,
    query: { enabled: !!userAddress && !!factoryAddress && !!collateralAddress },
  });
  const { data: collateralFactoryAllowance, refetch: refetchCollateralFactory } = useReadContract({
    address: factoryAddress,
    abi: factoryAbi,
    functionName: "allowance",
    args: collateralAddress && userAddress ? [collateralAddress, userAddress] : undefined,
    query: { enabled: !!userAddress && !!factoryAddress && !!collateralAddress },
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

  // Auto-mint + collateral approvals are sell-side. Don't bother checking on a Buy.
  const needsAutoMint = direction === "sell" && autoMintEnabled === false && !!factoryAddress;
  const needsCollateralApproval =
    direction === "sell" &&
    !!collateralAddress &&
    !!factoryAddress &&
    ((collateralErc20Allowance ?? 0n) === 0n || (collateralFactoryAllowance ?? 0n) === 0n);

  const { writeContract: approve, data: approvalHash, isPending: isApproving } = useWriteContract();
  const { isSuccess: approvalConfirmed } = useWaitForTransactionReceipt({ hash: approvalHash });

  const {
    writeContract: enableAutoMint,
    data: autoMintHash,
    isPending: isEnablingAutoMint,
  } = useWriteFactoryEnableAutoMintBurn();
  const { isSuccess: autoMintConfirmed } = useWaitForTransactionReceipt({ hash: autoMintHash });
  useEffect(() => {
    if (autoMintConfirmed) refetchAutoMint();
  }, [autoMintConfirmed, refetchAutoMint]);

  const {
    writeContract: factoryApprove,
    data: factoryApproveHash,
    isPending: isFactoryApproving,
  } = useWriteFactoryApprove();
  const { isSuccess: factoryApproveConfirmed } = useWaitForTransactionReceipt({ hash: factoryApproveHash });
  useEffect(() => {
    if (factoryApproveConfirmed) refetchCollateralFactory();
  }, [factoryApproveConfirmed, refetchCollateralFactory]);

  const {
    writeContract: factoryApproveOperator,
    data: factoryApproveOperatorHash,
    isPending: isApprovingOperator,
  } = useWriteFactoryApproveOperator();
  const { isSuccess: factoryApproveOperatorConfirmed } = useWaitForTransactionReceipt({
    hash: factoryApproveOperatorHash,
  });
  useEffect(() => {
    if (!factoryApproveOperatorConfirmed) return;
    refetchFactoryOperator();
    // L2s settle fast; mainnet's RPCs can lag a beat behind the receipt.
    const delay = chainId === 1 ? 10_000 : 1_000;
    const t = setTimeout(refetchFactoryOperator, delay);
    return () => clearTimeout(t);
  }, [factoryApproveOperatorConfirmed, refetchFactoryOperator, chainId]);

  useEffect(() => {
    if (approvalConfirmed) {
      refetchUsdcAllowance();
      refetchOptionAllowance();
      refetchCollateralErc20();
    }
  }, [approvalConfirmed, refetchUsdcAllowance, refetchOptionAllowance, refetchCollateralErc20]);

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
    if (!bebopRouter || !factoryAddress) return;
    factoryApproveOperator({ address: factoryAddress, args: [bebopRouter as `0x${string}`, true] });
  };

  const handleEnableAutoMint = () => {
    if (!factoryAddress) return;
    enableAutoMint({ address: factoryAddress, args: [true] });
  };

  // Two-layer collateral approval: mirror /mint's pattern. Fire whichever
  // layer is missing; the second click after confirmation handles the other.
  const handleApproveCollateral = () => {
    if (!collateralAddress || !factoryAddress) return;
    if ((collateralErc20Allowance ?? 0n) === 0n) {
      approve({
        address: collateralAddress,
        abi: ERC20_ABI,
        functionName: "approve",
        args: [factoryAddress, MAX_UINT],
      });
      return;
    }
    if ((collateralFactoryAllowance ?? 0n) === 0n) {
      factoryApprove({ address: factoryAddress, args: [collateralAddress, MAX_UINT] });
    }
  };

  const refetchAll = () => {
    refetchUsdcAllowance();
    refetchOptionAllowance();
    refetchUsdcBal();
    refetchOptBal();
    refetchAutoMint();
    refetchCollateralErc20();
    refetchCollateralFactory();
  };

  const resolvedCollateralSymbol =
    collateralSymbol ?? (collateralAddress ? `${collateralAddress.slice(0, 6)}…` : "Collateral");

  return {
    direction,
    optionAmountWei,
    optionDecimals,
    usdcDecimals,
    collateralSymbol: resolvedCollateralSymbol,
    usdcBalance: usdcBal?.value,
    optionBalance: optBal?.value,
    factoryOperatorApproved,
    usdcAllowance: usdcAllowance as bigint | undefined,
    optionAllowance: optionAllowance as bigint | undefined,
    needsUsdcApproval,
    handleApproveUsdc,
    needsOptionApproval,
    handleApproveOption,
    autoMintEnabled,
    needsAutoMint,
    handleEnableAutoMint,
    collateralErc20Allowance: collateralErc20Allowance as bigint | undefined,
    collateralFactoryAllowance: collateralFactoryAllowance as bigint | undefined,
    needsCollateralApproval,
    handleApproveCollateral,
    isApproving: isApproving || isEnablingAutoMint || isFactoryApproving || isApprovingOperator,
    allSatisfied:
      direction === "buy"
        ? !needsUsdcApproval
        : !needsOptionApproval && !needsAutoMint && !needsCollateralApproval,
    refetchAll,
  };
}
