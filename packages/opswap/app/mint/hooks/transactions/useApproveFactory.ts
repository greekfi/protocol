import { Address } from "viem";
import { useWriteContract } from "wagmi";
import { useFactoryAddress, useOptionFactoryContract } from "../useContracts";
import { MAX_UINT256 } from "../constants";

/**
 * Simple factory approve transaction executor
 * Just approves factory token spending, nothing else
 */
export function useApproveFactory() {
  const { writeContractAsync, isPending, error } = useWriteContract();
  const factoryAddress = useFactoryAddress();
  const factoryContract = useOptionFactoryContract();

  const approve = async (tokenAddress: Address) => {
    if (!factoryAddress || !factoryContract?.abi) {
      throw new Error("Factory not available");
    }

    const hash = await writeContractAsync({
      address: factoryAddress,
      abi: factoryContract.abi as readonly unknown[],
      functionName: "approve",
      args: [tokenAddress, MAX_UINT256],
    });
    return hash;
  };

  return { approve, isPending, error };
}
