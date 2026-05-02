import { useEffect } from "react";
import { parseUnits } from "viem";
import { useAccount, useChainId, useReadContract, useWaitForTransactionReceipt, useWriteContract } from "wagmi";
import {
  factoryAbi,
  useReadFactoryApprovedOperator,
  useReadFactoryAutoMintBurn,
  useWriteFactoryApprove,
  useWriteFactoryApproveOperator,
  useWriteFactoryEnableAutoMintBurn,
} from "~~/generated";
import deployedContracts from "~~/abi/deployedContracts";
import type { TradableOption } from "../../trade/hooks/useTradableOptions";

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

export interface SellApprovals {
  /** Parsed sell amount in option-token wei (bigint), or 0n when no input. */
  sellAmount: bigint;
  optionDecimals: number;

  autoMintEnabled: boolean | undefined;
  needsAutoMint: boolean;
  isEnablingAutoMint: boolean;
  handleEnableAutoMint: () => void;

  needsCollateralApproval: boolean;
  /** True iff one of the two collateral layers is granted but not both —
   *  drives the half-done (pink) pill state. */
  collateralPartial: boolean;
  handleApproveCollateral: () => void;

  factoryOperatorApproved: boolean | undefined;
  needsOptionApproval: boolean;
  handleApproveOption: () => void;

  needsUsdcApproval: boolean;
  handleApproveUsdc: () => void;

  isApproving: boolean;
  allSatisfied: boolean;
}

export function useSellApprovals(option: TradableOption | null, amount: string): SellApprovals {
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
  const sellAmount =
    option && amount && parseFloat(amount) > 0 ? parseUnits(amount, optionDecimals) : 0n;

  // Auto-mint flag.
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

  // Option → Bebop allowance (bypassed if factory operator is set).
  const { data: factoryOperatorApproved, refetch: refetchFactoryOperator } = useReadFactoryApprovedOperator({
    address: factoryAddress,
    args: userAddress && bebopRouter ? [userAddress, bebopRouter as `0x${string}`] : undefined,
    query: { enabled: !!userAddress && !!bebopRouter && !!factoryAddress },
  });
  const { data: optionAllowance, refetch: refetchOption } = useReadContract({
    address: optionToken,
    abi: ERC20_ABI,
    functionName: "allowance",
    args: userAddress && bebopRouter ? [userAddress, bebopRouter as `0x${string}`] : undefined,
    query: { enabled: !!userAddress && !!bebopRouter && !!optionToken },
  });

  // USDC → Bebop allowance (needed to buy back / close positions via Bebop later).
  const { data: usdcAllowance, refetch: refetchUsdc } = useReadContract({
    address: usdcAddress,
    abi: ERC20_ABI,
    functionName: "allowance",
    args: userAddress && bebopRouter ? [userAddress, bebopRouter as `0x${string}`] : undefined,
    query: { enabled: !!userAddress && !!bebopRouter },
  });

  // When the user has typed a deposit amount, require that allowance ≥ that
  // amount (so finite/non-MAX approvals are correctly tracked). Before they
  // type anything, fall back to "any allowance > 0".
  const collateralThreshold = sellAmount > 0n ? sellAmount : 1n;
  const collateralErc20Done = (collateralErc20Allowance ?? 0n) >= collateralThreshold;
  const collateralFactoryDone = (collateralFactoryAllowance ?? 0n) >= collateralThreshold;
  const needsCollateralApproval =
    !!factoryAddress && !!collateralAddress && (!collateralErc20Done || !collateralFactoryDone);
  const collateralPartial =
    needsCollateralApproval && (collateralErc20Done || collateralFactoryDone);
  const needsOptionApproval =
    !!bebopRouter &&
    !!optionToken &&
    optionAllowance !== undefined &&
    sellAmount > 0n &&
    optionAllowance < sellAmount &&
    !factoryOperatorApproved;
  const needsAutoMint = autoMintEnabled === false && !!factoryAddress;
  const needsUsdcApproval =
    !!bebopRouter && usdcAllowance !== undefined && usdcAllowance === 0n;

  const {
    writeContract: enableAutoMint,
    data: autoMintHash,
    isPending: isEnablingAutoMint,
  } = useWriteFactoryEnableAutoMintBurn();
  const { isSuccess: autoMintConfirmed } = useWaitForTransactionReceipt({ hash: autoMintHash });
  useEffect(() => {
    if (autoMintConfirmed) refetchAutoMint();
  }, [autoMintConfirmed, refetchAutoMint]);

  const { writeContract: approve, data: approvalHash, isPending: isApproving } = useWriteContract();
  const { isSuccess: approvalConfirmed } = useWaitForTransactionReceipt({ hash: approvalHash });
  useEffect(() => {
    if (!approvalConfirmed) return;
    // Refetch immediately, then again after a short delay — the RPC node
    // can lag a beat behind the receipt and return the pre-approval value
    // on the first read.
    refetchCollateralErc20();
    refetchOption();
    refetchUsdc();
    const delay = chainId === 1 ? 10_000 : 1_000;
    const t = setTimeout(() => {
      refetchCollateralErc20();
      refetchOption();
      refetchUsdc();
    }, delay);
    return () => clearTimeout(t);
  }, [approvalConfirmed, chainId, refetchCollateralErc20, refetchOption, refetchUsdc]);

  const {
    writeContract: factoryApprove,
    data: factoryApproveHash,
    isPending: isFactoryApproving,
  } = useWriteFactoryApprove();
  const { isSuccess: factoryApproveConfirmed } = useWaitForTransactionReceipt({
    hash: factoryApproveHash,
  });
  useEffect(() => {
    if (!factoryApproveConfirmed) return;
    refetchCollateralFactory();
    // RPC nodes can lag a beat behind the receipt — nudge the read.
    const delay = chainId === 1 ? 10_000 : 1_000;
    const t = setTimeout(refetchCollateralFactory, delay);
    return () => clearTimeout(t);
  }, [factoryApproveConfirmed, refetchCollateralFactory, chainId]);

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

  const handleEnableAutoMint = () => {
    if (!factoryAddress) return;
    enableAutoMint({ address: factoryAddress, args: [true] });
  };
  // Two-layer collateral approval: fire whichever layer is missing. The user
  // taps the row twice (once per layer); the pill flips pink between them.
  const handleApproveCollateral = () => {
    if (!factoryAddress || !collateralAddress) return;
    if (!collateralErc20Done) {
      approve({
        address: collateralAddress,
        abi: ERC20_ABI,
        functionName: "approve",
        args: [factoryAddress, MAX_UINT],
      });
      return;
    }
    if (!collateralFactoryDone) {
      factoryApprove({ address: factoryAddress, args: [collateralAddress, MAX_UINT] });
    }
  };
  const handleApproveOption = () => {
    if (!bebopRouter || !factoryAddress) return;
    factoryApproveOperator({ address: factoryAddress, args: [bebopRouter as `0x${string}`, true] });
  };
  const handleApproveUsdc = () => {
    if (!bebopRouter) return;
    approve({
      address: usdcAddress,
      abi: ERC20_ABI,
      functionName: "approve",
      args: [bebopRouter as `0x${string}`, MAX_UINT],
    });
  };

  return {
    sellAmount,
    optionDecimals,
    autoMintEnabled,
    needsAutoMint,
    isEnablingAutoMint,
    handleEnableAutoMint,
    needsCollateralApproval,
    collateralPartial,
    handleApproveCollateral,
    factoryOperatorApproved,
    needsOptionApproval,
    handleApproveOption,
    needsUsdcApproval,
    handleApproveUsdc,
    isApproving: isApproving || isApprovingOperator || isFactoryApproving,
    // USDC approval is optional (only needed to close positions later); don't block Deposit on it.
    allSatisfied: !needsAutoMint && !needsCollateralApproval && !needsOptionApproval,
  };
}
