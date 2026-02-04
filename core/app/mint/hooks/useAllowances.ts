import { useMemo } from "react";
import type { AllowanceState } from "./types";
import { useContracts } from "./useContracts";
import { Address, erc20Abi } from "viem";
import { useAccount, useReadContracts } from "wagmi";

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
  const deployedContracts = useContracts();
  const factoryAddress = deployedContracts?.OptionFactory?.address;
  const factoryContract = deployedContracts?.OptionFactory;

  const enabled = Boolean(tokenAddress && userAddress && factoryAddress && factoryContract?.abi);

  // Build contracts array for multicall - check both allowances at once
  const contracts = useMemo(() => {
    if (!enabled || !tokenAddress || !userAddress || !factoryAddress || !factoryContract?.abi) {
      return [];
    }

    return [
      // ERC20 allowance: token.allowance(user, factory)
      {
        address: tokenAddress,
        abi: erc20Abi,
        functionName: "allowance" as const,
        args: [userAddress, factoryAddress] as const,
      },
      // Factory internal allowance: factory.allowance(token, user)
      {
        address: factoryAddress,
        abi: factoryContract.abi as readonly unknown[],
        functionName: "allowance" as const,
        args: [tokenAddress, userAddress] as const,
      },
    ];
  }, [enabled, tokenAddress, userAddress, factoryAddress, factoryContract?.abi]);

  const { data, isLoading, refetch } = useReadContracts({
    contracts: contracts as any,
    query: {
      enabled: contracts.length > 0,
    },
  });

  return useMemo(() => {
    const erc20 = (data?.[0]?.result as bigint) ?? 0n;
    const factory = (data?.[1]?.result as bigint) ?? 0n;

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
