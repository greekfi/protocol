import { addressedTokensForChain, type AddressedToken } from "../../data/tokens";
import { useContracts } from "./useContracts";
import { useBrowseChainId } from "../../hooks/useBrowseChain";

export type Token = AddressedToken;

/**
 * Returns every token deployed on the current browse chain in the
 * `{address, symbol, decimals}` shape consumers expect, keyed by symbol.
 *
 * Source of truth is `core/app/data/tokens.ts` — one canonical table for
 * every page on every chain. This hook only adds the runtime concerns:
 * resolving the chain, and (on test chains) splicing in the deployed
 * StableToken / ShakyToken mocks.
 */
export const useTokenMap = () => {
  const chainId = useBrowseChainId();
  const contract = useContracts();

  // StableToken / ShakyToken are only deployed on test chains (foundry,
  // base, arbitrum). Mainnet/Ink don't have them. Use `in` checks so the
  // contract-map union narrows correctly.
  const stableTokenAddress = contract && "StableToken" in contract ? contract.StableToken.address : undefined;
  const shakyTokenAddress = contract && "ShakyToken" in contract ? contract.ShakyToken.address : undefined;

  const baseTokensMap: Record<string, Token> = {};
  for (const t of addressedTokensForChain(chainId)) {
    baseTokensMap[t.symbol] = t;
  }

  if (chainId !== 1 && stableTokenAddress && shakyTokenAddress) {
    baseTokensMap["STK"] = { address: stableTokenAddress, symbol: "STK", decimals: 18 };
    baseTokensMap["SHK"] = { address: shakyTokenAddress, symbol: "SHK", decimals: 18 };
  }

  return { allTokensMap: baseTokensMap };
};
