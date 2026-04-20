import { useMemo } from "react";
import type { AllowanceState } from "./types";
import { useContracts } from "./useContracts";
import { Address, erc20Abi } from "viem";
import { useAccount, useReadContracts } from "wagmi";
import { factoryAbi } from "~~/generated";

/**
 * Hook to check both allowances for a token to the OptionFactory
 *
 * The factory has a two-layer approval system:
 * 1. ERC20 approval: token.approve(factory, amount)
 * 2. Factory internal: factory.approve(token, amount)
 *
 * Both must be set before mint/exercise operations.
 *
 * @param tokenAddress - The ERC20 token to check allowances for
 * @param requiredAmount - The amount needed (defaults to 0)
 * @returns AllowanceState with both allowance values and approval needs
 */
export function useAllowances(
  tokenAddress: Address | undefined,
  requiredAmount: bigint = 0n,
): AllowanceState & {
  isLoading: boolean;
  refetch: () => void;
} {
  const { address: userAddress } = useAccount();
  const factoryAddress = useContracts()?.Factory?.address as Address | undefined;

  const enabled = Boolean(tokenAddress && userAddress && factoryAddress);

  // Both allowances in one multicall
  const contracts = useMemo(() => {
    if (!enabled || !tokenAddress || !userAddress || !factoryAddress) return [];
    return [
      // token.allowance(user, factory)
      {
        address: tokenAddress,
        abi: erc20Abi,
        functionName: "allowance" as const,
        args: [userAddress, factoryAddress] as const,
      },
      // factory.allowance(token, user)
      {
        address: factoryAddress,
        abi: factoryAbi,
        functionName: "allowance" as const,
        args: [tokenAddress, userAddress] as const,
      },
    ] as const;
  }, [enabled, tokenAddress, userAddress, factoryAddress]);

  // Wagmi wants a literal tuple to infer per-call return types; our dynamic
  // array needs a single cast here. Per-item types are still enforced by the
  // generated abi, so the safety we care about (wrong functionName, wrong
  // args shape) is still compile-time.
  const { data, isLoading, refetch } = useReadContracts({
    contracts: contracts as readonly unknown[] as never,
    query: { enabled: contracts.length > 0 },
  });

  return useMemo(() => {
    const results = data as Array<{ result?: unknown }> | undefined;
    const erc20 = (results?.[0]?.result as bigint | undefined) ?? 0n;
    const factory = (results?.[1]?.result as bigint | undefined) ?? 0n;

    const needsErc20Approval = erc20 < requiredAmount;
    const needsFactoryApproval = factory < requiredAmount;
    const isFullyApproved = !needsErc20Approval && !needsFactoryApproval;

    return {
      erc20Allowance: erc20,
      factoryAllowance: factory,
      needsErc20Approval,
      needsFactoryApproval,
      isFullyApproved,
      isLoading,
      refetch,
    };
  }, [data, requiredAmount, isLoading, refetch]);
}

/**
 * Hook to check ERC20 allowance only (simpler version)
 * Use this when you only need to check the token → spender approval
 */
export function useErc20Allowance(tokenAddress: Address | undefined, spender: Address | undefined) {
  const { address: userAddress } = useAccount();

  const enabled = Boolean(tokenAddress && userAddress && spender);

  const contracts = useMemo(() => {
    if (!enabled || !tokenAddress || !userAddress || !spender) return [];
    return [
      {
        address: tokenAddress,
        abi: erc20Abi,
        functionName: "allowance" as const,
        args: [userAddress, spender] as const,
      },
    ];
  }, [enabled, tokenAddress, userAddress, spender]);

  const { data, isLoading, refetch } = useReadContracts({
    contracts: contracts as any,
    query: {
      enabled: contracts.length > 0,
    },
  });

  return {
    allowance: (data?.[0]?.result as bigint) ?? 0n,
    isLoading,
    refetch,
  };
}

export default useAllowances;
