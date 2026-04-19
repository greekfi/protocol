import { useContracts } from "../useContracts";
import { Address } from "viem";
import { useWriteContract } from "wagmi";

/**
 * Simple mint transaction executor
 * Just calls mint() on the option contract, nothing else
 */
export function useMintTransaction() {
  const { writeContractAsync, isPending, error } = useWriteContract();
  const optionContract = useContracts()?.Option;

  const mint = async (optionAddress: Address, amount: bigint) => {
    if (!optionContract?.abi) {
      throw new Error("Option contract not available");
    }

    const hash = await writeContractAsync({
      address: optionAddress,
      abi: optionContract.abi as readonly unknown[],
      functionName: "mint",
      args: [amount],
    });
    return hash;
  };

  return { mint, isPending, error };
}
