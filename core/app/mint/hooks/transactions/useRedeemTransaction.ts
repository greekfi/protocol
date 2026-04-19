import { useContracts } from "../useContracts";
import { Address } from "viem";
import { useWriteContract } from "wagmi";

/**
 * Simple redeem transaction executor
 * Just calls redeem() on the option contract, nothing else
 */
export function useRedeemTransaction() {
  const { writeContractAsync, isPending, error } = useWriteContract();
  const optionContract = useContracts()?.Option;

  const redeem = async (optionAddress: Address, amount: bigint) => {
    if (!optionContract?.abi) {
      throw new Error("Option contract not available");
    }

    const hash = await writeContractAsync({
      address: optionAddress,
      abi: optionContract.abi as readonly unknown[],
      functionName: "redeem",
      args: [amount],
    });
    return hash;
  };

  return { redeem, isPending, error };
}
