import tokenList from "../tokenListLocal.json";
import { useContract } from "./contract";

export interface Token {
  address: string;
  symbol: string;
  decimals: number;
}

export const useTokenMap = () => {
  const contract = useContract();
  const stableToken = contract?.StableToken;
  const shakyToken = contract?.ShakyToken;

  // Create a map of all tokens for easy lookup
  const allTokensMap = tokenList.reduce(
    (acc, token) => {
      acc[token.symbol] = token;
      return acc;
    },
    {} as Record<string, Token>,
  );

  // If we have stable and shaky tokens, override the token list
  if (stableToken && shakyToken) {
    Object.keys(allTokensMap).forEach(key => {
      delete allTokensMap[key];
    });
    allTokensMap["STK"] = {
      address: stableToken.address,
      symbol: "STK",
      decimals: 18,
    };
    allTokensMap["SHK"] = {
      address: shakyToken.address,
      symbol: "SHK",
      decimals: 18,
    };
  }

  return {
    allTokensMap,
  };
};
