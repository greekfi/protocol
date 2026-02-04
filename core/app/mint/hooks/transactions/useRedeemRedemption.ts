import { useContracts } from "../useContracts";
import { Address } from "viem";
import { useWriteContract } from "wagmi";

/**
 * Redemption token redeem executor (post-expiration)
 * Burns Redemption tokens to get collateral or consideration back after expiration
 */
export function useRedeemRedemption() {
  const { writeContractAsync, isPending, error } = useWriteContract();
  const redemptionContract = useContracts()?.Redemption;

  const redeem = async (redemptionAddress: Address, amount: bigint) => {
    console.log("=== useRedeemRedemption.redeem ===");
    console.log("redemptionAddress:", redemptionAddress);
    console.log("amount:", amount.toString());
    console.log("redemptionContract:", redemptionContract);
    console.log("redemptionContract.abi exists:", Boolean(redemptionContract?.abi));

    if (!redemptionContract?.abi) {
      console.error("Redemption contract not available");
      throw new Error("Redemption contract not available");
    }

    console.log("Calling writeContractAsync...");
    const hash = await writeContractAsync({
      address: redemptionAddress,
      abi: redemptionContract.abi as readonly unknown[],
      functionName: "redeem",
      args: [amount],
    });
    console.log("redeem transaction hash:", hash);
    return hash;
  };

  const redeemConsideration = async (redemptionAddress: Address, amount: bigint) => {
    console.log("=== useRedeemRedemption.redeemConsideration ===");
    console.log("redemptionAddress:", redemptionAddress);
    console.log("amount:", amount.toString());
    console.log("redemptionContract:", redemptionContract);
    console.log("redemptionContract.abi exists:", Boolean(redemptionContract?.abi));

    if (!redemptionContract?.abi) {
      console.error("Redemption contract not available");
      throw new Error("Redemption contract not available");
    }

    console.log("Calling writeContractAsync...");
    const hash = await writeContractAsync({
      address: redemptionAddress,
      abi: redemptionContract.abi as readonly unknown[],
      functionName: "redeemConsideration",
      args: [amount],
    });
    console.log("redeemConsideration transaction hash:", hash);
    return hash;
  };

  return { redeem, redeemConsideration, isPending, error };
}
