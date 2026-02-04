import { useContracts } from "../useContracts";
import { Address } from "viem";
import { useReadContract, useWriteContract } from "wagmi";

/**
 * Simple Redemption token transfer executor
 * Transfers Redemption tokens to another address
 */
export function useTransferRedemption() {
  const { writeContractAsync, isPending, error } = useWriteContract();
  const redemptionContract = useContracts()?.Redemption;

  const transfer = async (redemptionAddress: Address, to: Address, amount: bigint) => {
    if (!redemptionContract?.abi) {
      throw new Error("Redemption contract not available");
    }

    const hash = await writeContractAsync({
      address: redemptionAddress,
      abi: redemptionContract.abi as readonly unknown[],
      functionName: "transfer",
      args: [to, amount],
    });
    return hash;
  };

  return { transfer, isPending, error };
}
