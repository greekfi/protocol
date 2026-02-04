import { useContracts } from "../useContracts";
import { Address } from "viem";
import { useWriteContract } from "wagmi";

/**
 * Simple Option token transfer executor
 * Transfers Option tokens to another address
 */
export function useTransferOption() {
  const { writeContractAsync, isPending, error } = useWriteContract();
  const optionContract = useContracts()?.Option;

  const transfer = async (optionAddress: Address, to: Address, amount: bigint) => {
    if (!optionContract?.abi) {
      throw new Error("Option contract not available");
    }

    const hash = await writeContractAsync({
      address: optionAddress,
      abi: optionContract.abi as readonly unknown[],
      functionName: "transfer",
      args: [to, amount],
    });
    return hash;
  };

  return { transfer, isPending, error };
}
