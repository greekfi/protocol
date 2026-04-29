import tokenList from "../data/tokenList.json";
import { useContracts } from "./useContracts";
import { useBrowseChainId } from "../../hooks/useBrowseChain";

export interface Token {
  address: string;
  symbol: string;
  decimals: number;
}

export const useTokenMap = () => {
  // Use the browse chain (which mirrors the wallet chain when connected) so
  // chain-scoped UI stays consistent: when a user flips the chain selector
  // without a wallet, the token list reflects the picked chain too.
  const chainId = useBrowseChainId();
  const contract = useContracts();

  const stableTokenAddress = contract?.StableToken?.address;
  const shakyTokenAddress = contract?.ShakyToken?.address;

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

  // console.log("useTokenMap - allTokensMap:", baseTokensMap);
  // console.log("useTokenMap - chainId:", chainId, "STK:", stableTokenAddress, "SHK:", shakyTokenAddress);

  return {
    allTokensMap: baseTokensMap,
  };
};
