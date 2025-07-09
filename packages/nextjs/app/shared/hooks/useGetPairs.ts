import { useContract } from "./useContract";
import { Address } from "viem";
import { useReadContract } from "wagmi";

export interface OptionPair {
  collateral: Address;
  consideration: Address;
}

export const useGetPairs = () => {
  const contract = useContract();
  const abi = contract?.OptionFactory?.abi;

  const {
    data: pairs,
    error,
    refetch,
    isLoading,
  } = useReadContract({
    address: contract?.OptionFactory?.address,
    abi,
    functionName: "getPairs",
    query: {
      enabled: !!contract?.OptionFactory?.address,
    },
  });

  return {
    pairs: (pairs as OptionPair[]) || [],
    error,
    refetch,
    isLoading,
  };
};
