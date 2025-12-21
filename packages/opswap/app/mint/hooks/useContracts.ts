import { useMemo } from "react";
import { useChainId } from "wagmi";
import deployedContracts from "~~/contracts/deployedContracts";

// Extract chain IDs from deployed contracts
type SupportedChainId = keyof typeof deployedContracts;

// Extract contract names for a given chain
type ContractName<TChainId extends SupportedChainId> = keyof (typeof deployedContracts)[TChainId];

// Get the contract config type for a specific contract
type ContractConfig<
  TChainId extends SupportedChainId,
  TName extends ContractName<TChainId>,
> = (typeof deployedContracts)[TChainId][TName];

/**
 * Hook to get all deployed contracts for the current chain
 * @returns All contracts for the current chain, or null if chain not supported
 */
export function useContracts() {
  const chainId = useChainId();

  return useMemo(() => {
    const contracts = deployedContracts[chainId as SupportedChainId];
    if (!contracts) {
      console.warn(`No contracts deployed for chainId ${chainId}`);
      return null;
    }
    return contracts;
  }, [chainId]);
}

/**
 * Hook to get a specific contract's config (address + abi)
 * @param name - The contract name (e.g., "OptionFactory", "Option")
 * @returns The contract config or null if not found
 */
export function useContract<TName extends string>(name: TName) {
  const contracts = useContracts();

  return useMemo(() => {
    if (!contracts) return null;
    const contract = (contracts as Record<string, { address: string; abi: readonly unknown[] }>)[name];
    return contract ?? null;
  }, [contracts, name]);
}

/**
 * Hook to get the OptionFactory contract config
 */
export function useOptionFactoryContract() {
  return useContract("OptionFactory");
}

/**
 * Hook to get the Option template contract config
 * Note: This is the template, not deployed option instances
 */
export function useOptionContract() {
  return useContract("Option");
}

/**
 * Hook to get the Redemption template contract config
 * Note: This is the template, not deployed redemption instances
 */
export function useRedemptionContract() {
  return useContract("Redemption");
}

/**
 * Get the factory address for the current chain
 */
export function useFactoryAddress() {
  const factory = useOptionFactoryContract();
  return factory?.address as `0x${string}` | undefined;
}
