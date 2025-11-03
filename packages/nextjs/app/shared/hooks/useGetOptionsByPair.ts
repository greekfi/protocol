import { useContract } from "./useContract";
import { Address } from "viem";
import { useReadContract } from "wagmi";

export interface OptionData {
  longOption: Address;
  shortOption: Address;
  longSymbol: string;
  shortSymbol: string;
  collateralName: string;
  considerationName: string;
  collateralSymbol: string;
  considerationSymbol: string;
  collateralDecimals: number;
  considerationDecimals: number;
  collateral: Address;
  consideration: Address;
  expiration: bigint;
  strike: bigint;
  isPut: boolean;
}

export interface OptionPlus extends OptionData {
  strikePrice: number;
}

export interface ExpirationGroup {
  expirationDate: bigint;
  formattedDate: string;
  options: OptionPlus[];
}

/**
 * Calculates the visual (human-readable) strike price for an option.
 * For a call: strike / 10^collateralDecimals
 * For a put:  strike / 10^considerationDecimals
 * Returns a string for display.
 */
/**
 * Converts a human-readable strike price string back to the on-chain integer representation.
 * This is the inverse of getVisualStrikePrice.
 * For a call: strikeInteger = strikePrice * 10^(18 + considerationDecimals - collateralDecimals)
 * For a put:  strikeInteger = (1/strikePrice) * 10^(18 + considerationDecimals - collateralDecimals)
 * Accepts a string input (e.g. "123.45") and returns a BigInt.
 */

export function getOnChainStrikePrice(
  strikePrice: bigint,
  isPut: boolean,
  collateralDecimals: number,
  considerationDecimals: number,
): number {
  const strike = strikePrice / BigInt(10 ** (18 + considerationDecimals - collateralDecimals));
  return isPut ? 1 / Number(strike) : Number(strike);
}

export const useGetOptionsByPair = (collateralAddress: Address, considerationAddress: Address) => {
  const contract = useContract();
  const abi = contract?.OptionFactory?.abi;

  // Get all options for the specified pair using the contract's getPairToOptions function
  const {
    data: options,
    error,
    refetch,
  } = useReadContract({
    address: contract?.OptionFactory?.address,
    abi,
    functionName: "get",
    args: [collateralAddress, considerationAddress],
    query: {
      enabled: !!contract?.OptionFactory?.address,
    },
  });

  // Convert the contract response to our OptionData format
  const filteredOptions: OptionPlus[] = [];

  if (options) {
    // The contract returns an array of Option structs
    for (const option of options as any[]) {
      filteredOptions.push({
        longOption: option.longOption,
        shortOption: option.shortOption,
        longSymbol: option.longSymbol,
        shortSymbol: option.shortSymbol,
        collateralName: option.collateralName,
        considerationName: option.considerationName,
        collateralSymbol: option.collateralSymbol,
        considerationSymbol: option.considerationSymbol,
        collateralDecimals: Number(option.collateralDecimals),
        considerationDecimals: Number(option.considerationDecimals),
        collateral: option.collateral,
        consideration: option.consideration,
        expiration: option.expiration,
        strike: option.strike,
        isPut: option.isPut,
        strikePrice: getOnChainStrikePrice(
          option.strike,
          option.isPut,
          option.collateralDecimals,
          option.considerationDecimals,
        ),
      });
    }
  }

  // Group by expiration date
  const expirationGroups: ExpirationGroup[] = [];
  const groupedByExpiration = new Map<string, OptionPlus[]>();

  filteredOptions.forEach(option => {
    const expirationKey = option.expiration.toString();
    if (!groupedByExpiration.has(expirationKey)) {
      groupedByExpiration.set(expirationKey, []);
    }
    groupedByExpiration.get(expirationKey)!.push(option);
  });

  // Convert to array and sort by expiration date
  groupedByExpiration.forEach((options, expirationKey) => {
    const expirationDate = BigInt(expirationKey);
    const formattedDate = new Date(Number(expirationDate) * 1000).toLocaleDateString();

    // Sort options by strike price
    const sortedOptions = options.sort((a, b) => Number(a.strike - b.strike));

    expirationGroups.push({
      expirationDate,
      formattedDate,
      options: sortedOptions,
    });
  });

  // Sort expiration groups by date
  expirationGroups.sort((a, b) => Number(a.expirationDate - b.expirationDate));

  return {
    options: filteredOptions,
    expirationGroups,
    error,
    refetch,
  };
};
