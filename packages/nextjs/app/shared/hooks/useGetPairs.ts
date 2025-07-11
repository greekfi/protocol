import { useContract } from "./useContract";
import { Address } from "viem";
import { useReadContract } from "wagmi";

export interface OptionPair {
  collateral: Address;
  consideration: Address;
  collateralName: string;
  considerationName: string;
  collateralDecimals: number;
  considerationDecimals: number;
  collateralSymbol: string;
  considerationSymbol: string;
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
  // Ensure unique pairs by stringifying each pair as a key in a Map
  const uniquePairsMap = new Map<string, OptionPair>();
  if (Array.isArray(pairs)) {
    for (const pair of pairs) {
      // Create a unique key for each pair based on its addresses
      const key = `${pair.collateral.toLowerCase()}-${pair.consideration.toLowerCase()}`;
      if (!uniquePairsMap.has(key)) {
        uniquePairsMap.set(key, pair);
      }
    }
  }
  const uniquePairs = Array.from(uniquePairsMap.values());

  return {
    pairs: uniquePairs as OptionPair[],
    error,
    refetch,
    isLoading,
  };
};
