import { useContracts } from "./useContracts";
import { useOptions } from "./useOptions";
import { Address } from "viem";
import { useReadContract, useWriteContract } from "wagmi";

/**
 * Hook for claiming accumulated fees from all options via OptionFactory
 */
export function useClaimFees() {
  const { writeContractAsync, isPending, error } = useWriteContract();
  const contracts = useContracts();
  const optionFactoryContract = contracts?.OptionFactory;
  const { options } = useOptions();

  const claimFees = async () => {
    if (!optionFactoryContract?.abi || !optionFactoryContract?.address) {
      throw new Error("OptionFactory contract not available");
    }

    if (!options || options.length === 0) {
      throw new Error("No options available");
    }

    // Extract option addresses
    const optionAddresses = options.map(opt => opt.address);

    // Extract unique collateral addresses
    const uniqueCollaterals = Array.from(new Set(options.map(opt => opt.collateral)));

    const hash = await writeContractAsync({
      address: optionFactoryContract.address as Address,
      abi: optionFactoryContract.abi as readonly unknown[],
      functionName: "claimFees",
      args: [optionAddresses, uniqueCollaterals],
    });
    return hash;
  };

  return { claimFees, isPending, error };
}

/**
 * Hook for reading accumulated fees for an option
 */
export function useReadFees(optionAddress: Address) {
  const contracts = useContracts();
  const optionContract = contracts?.Option;

  // First, get the redemption contract address from the option
  const { data: redemptionAddress } = useReadContract({
    address: optionAddress,
    abi: optionContract?.abi as readonly unknown[],
    functionName: "redemption",
  });

  // Then, read the fees from the redemption contract
  const { data: fees, refetch } = useReadContract({
    address: redemptionAddress as Address,
    abi: contracts?.Redemption?.abi as readonly unknown[],
    functionName: "fees",
  });

  return { fees: fees as bigint | undefined, refetch };
}

/**
 * Hook for reading total fees across all options
 */
export function useReadAllFees() {
  const { options } = useOptions();
  const contracts = useContracts();

  // Read fees for each option's redemption contract
  const allFees = options?.map(option => {
    // eslint-disable-next-line react-hooks/rules-of-hooks
    const { data: redemptionAddress } = useReadContract({
      address: option.address,
      abi: contracts?.Option?.abi as readonly unknown[],
      functionName: "redemption",
    });

    // eslint-disable-next-line react-hooks/rules-of-hooks
    const { data: fees } = useReadContract({
      address: redemptionAddress as Address,
      abi: contracts?.Redemption?.abi as readonly unknown[],
      functionName: "fees",
    });

    return {
      optionAddress: option.address,
      collateral: option.collateral,
      fees: fees as bigint | undefined,
    };
  });

  // Calculate total fees (simplified - just counts number of options with fees)
  const totalFees =
    allFees?.reduce((sum, item) => {
      return sum + (item.fees || 0n);
    }, 0n) || 0n;

  return { allFees, totalFees, hasAnyFees: totalFees > 0n };
}
