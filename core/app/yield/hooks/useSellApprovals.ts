import { useEffect } from "react";
import { parseUnits } from "viem";
import { useAccount, useChainId, useReadContract, useWaitForTransactionReceipt, useWriteContract } from "wagmi";
import {
  useReadFactoryApprovedOperator,
  useReadFactoryAutoMintBurn,
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

  // Collateral → Factory allowance.
  const { data: collateralAllowance, refetch: refetchCollateral } = useReadContract({
    address: collateralAddress,
    abi: ERC20_ABI,
    functionName: "allowance",
    args: userAddress && factoryAddress ? [userAddress, factoryAddress] : undefined,
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

  const needsCollateralApproval =
    !!factoryAddress &&
    !!collateralAddress &&
    collateralAllowance !== undefined &&
    sellAmount > 0n &&
    collateralAllowance < sellAmount;
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
    if (approvalConfirmed) {
      refetchCollateral();
      refetchOption();
      refetchUsdc();
    }
  }, [approvalConfirmed, refetchCollateral, refetchOption, refetchUsdc]);

  const {
    writeContract: factoryApproveOperator,
    data: factoryApproveOperatorHash,
    isPending: isApprovingOperator,
  } = useWriteFactoryApproveOperator();
  const { isSuccess: factoryApproveOperatorConfirmed } = useWaitForTransactionReceipt({
    hash: factoryApproveOperatorHash,
  });
  useEffect(() => {
    if (factoryApproveOperatorConfirmed) refetchFactoryOperator();
  }, [factoryApproveOperatorConfirmed, refetchFactoryOperator]);

  const handleEnableAutoMint = () => {
    if (!factoryAddress) return;
    enableAutoMint({ address: factoryAddress, args: [true] });
  };
  const handleApproveCollateral = () => {
    if (!factoryAddress || !collateralAddress) return;
    approve({
      address: collateralAddress,
      abi: ERC20_ABI,
      functionName: "approve",
      args: [factoryAddress, MAX_UINT],
    });
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
    handleApproveCollateral,
    factoryOperatorApproved,
    needsOptionApproval,
    handleApproveOption,
    needsUsdcApproval,
    handleApproveUsdc,
    isApproving: isApproving || isApprovingOperator,
    // USDC approval is optional (only needed to close positions later); don't block Deposit on it.
    allSatisfied: !needsAutoMint && !needsCollateralApproval && !needsOptionApproval,
  };
}
