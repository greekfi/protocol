import type { Balances, OptionDetails, OptionInfo } from "./types";
import { useContracts } from "./useContracts";
import { Address } from "viem";
import { useAccount, useReadContracts } from "wagmi";

/**
 * Check if an option has expired
 */
function isExpired(expiration: bigint | undefined): boolean {
  if (!expiration) return false;
  return BigInt(Math.floor(Date.now() / 1000)) >= expiration;
}

/**
 * Format option name for display
 * Input: "OPT-COLL-CONS-STRIKE-YYYY-MM-DD" or similar
 */
function formatOptionName(name: string): string {
  if (!name) return "";

  const parts = name.split("-");
  if (parts.length < 4) return name;

  // Parse the name format: OPT-COLL-CONS-STRIKE-DATE
  const [prefix, collateral, consideration, strike, ...dateParts] = parts;
  const isPut = prefix?.includes("P") ?? false;
  const optionType = isPut ? "PUT" : "CALL";
  const date = dateParts.join("-");

  return `${optionType} ${collateral}/${consideration} @ ${strike} (${date})`;
}

/**
 * Hook to fetch all data for a single option contract
 * Combines details(), balancesOf(), and name() in one multicall
 *
 * @param optionAddress - The deployed option contract address
 * @returns Option details with balances, expiry status, and formatted name
 */
export function useOption(optionAddress: Address | undefined) {
  const { address: userAddress } = useAccount();
  const optionContract = useContracts()?.Option;

  const enabled = Boolean(
    optionAddress &&
    optionAddress !== "0x0" &&
    optionAddress !== "0x0000000000000000000000000000000000000000" &&
    optionContract?.abi,
  );

  // Build contracts array for multicall
  let contracts: any[] = [];

  if (enabled && optionContract?.abi) {
    contracts = [
      {
        address: optionAddress as Address,
        abi: optionContract.abi as readonly unknown[],
        functionName: "details" as const,
      },
      {
        address: optionAddress as Address,
        abi: optionContract.abi as readonly unknown[],
        functionName: "name" as const,
      },
    ];

    // Only add balancesOf if user is connected
    if (userAddress) {
      contracts.push({
        address: optionAddress as Address,
        abi: optionContract.abi as readonly unknown[],
        functionName: "balancesOf" as const,
        args: [userAddress],
      });
    }
  }

  const { data, isLoading, error, refetch } = useReadContracts({
    contracts: contracts as any,
    query: {
      enabled: contracts.length > 0,
    },
  });

  // Parse results
  if (!data || data.length === 0) {
    return {
      data: null,
      isLoading,
      error,
      refetch,
    };
  }

  const [detailsResult, nameResult, balancesResult] = data;

  console.log("=== useOption Debug ===");
  console.log("optionAddress:", optionAddress);
  console.log("userAddress:", userAddress);
  console.log("detailsResult:", detailsResult);
  console.log("nameResult:", nameResult);
  console.log("balancesResult:", balancesResult);

  // Check for errors in individual calls
  if (detailsResult?.status === "failure") {
    console.error("Details call failed:", detailsResult);
    return {
      data: null,
      isLoading,
      error: new Error("Failed to fetch option details"),
      refetch,
    };
  }

  const details = detailsResult?.result as OptionInfo | undefined;
  const name = nameResult?.result as string | undefined;
  const balances = balancesResult?.result as Balances | undefined;

  console.log("Parsed balances:", balances);

  if (!details) {
    return {
      data: null,
      isLoading,
      error,
      refetch,
    };
  }

  const optionDetails: OptionDetails = {
    ...details,
    isExpired: isExpired(details.expiration),
    balances: balances ?? null,
    formattedName: formatOptionName(name ?? ""),
  };

  return {
    data: optionDetails,
    isLoading,
    error,
    refetch,
  };
}

export default useOption;
