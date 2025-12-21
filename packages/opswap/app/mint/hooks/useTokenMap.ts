import { useMemo } from "react";
import tokenList from "../tokenList.json";
import { useContract } from "./useContract";
import { useChainId } from "wagmi";

export interface Token {
  address: string;
  symbol: string;
  decimals: number;
}

export const useTokenMap = () => {
  const chainId = useChainId();
  const contract = useContract();
  console.log("useTokenMap - chainId:", chainId);

  // Extract addresses to use as stable dependencies
  const stableTokenAddress = contract?.StableToken?.address;
  const shakyTokenAddress = contract?.ShakyToken?.address;

  // Memoize the token map to prevent recreation on every render
  const allTokensMap = useMemo(() => {
    const chainKey = String(chainId) as keyof typeof tokenList;
    const baseTokensMap = (tokenList[chainKey] ?? []).reduce(
      (acc, token) => {
        acc[token.symbol] = token;
        return acc;
      },
      {} as Record<string, Token>,
    );

    // If we have stable and shaky tokens, add them to the map
    if (chainId != 1 && stableTokenAddress && shakyTokenAddress) {
      baseTokensMap["STK"] = {
        address: stableTokenAddress,
        symbol: "STK",
        decimals: 18,
      };
      baseTokensMap["SHK"] = {
        address: shakyTokenAddress,
        symbol: "SHK",
        decimals: 18,
      };
    }

    return baseTokensMap;
  }, [chainId, stableTokenAddress, shakyTokenAddress]);

  return {
    allTokensMap,
  };
};
