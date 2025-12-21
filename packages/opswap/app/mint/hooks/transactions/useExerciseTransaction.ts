import { Address } from "viem";
import { useWriteContract } from "wagmi";
import { useOptionContract } from "../useContracts";

/**
 * Simple exercise transaction executor
 * Just calls exercise() on the option contract, nothing else
 */
export function useExerciseTransaction() {
  const { writeContractAsync, isPending, error } = useWriteContract();
  const optionContract = useOptionContract();

  const exercise = async (optionAddress: Address, amount: bigint) => {
    if (!optionContract?.abi) {
      throw new Error("Option contract not available");
    }

    const hash = await writeContractAsync({
      address: optionAddress,
      abi: optionContract.abi as readonly unknown[],
      functionName: "exercise",
      args: [amount],
    });
    return hash;
  };

  return { exercise, isPending, error };
}
