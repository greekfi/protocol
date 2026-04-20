import type { Balances, OptionDetails, OptionInfo } from "./types";
import { Address } from "viem";
import { useAccount, useReadContracts } from "wagmi";
import { optionAbi } from "~~/generated";

function isExpired(expiration: bigint | undefined): boolean {
  if (!expiration) return false;
  return BigInt(Math.floor(Date.now() / 1000)) >= expiration;
}

function formatOptionName(name: string): string {
  if (!name) return "";
  const parts = name.split("-");
  if (parts.length < 4) return name;
  const [prefix, collateral, consideration, strike, ...dateParts] = parts;
  const isPut = prefix?.includes("P") ?? false;
  const optionType = isPut ? "PUT" : "CALL";
  const date = dateParts.join("-");
  return `${optionType} ${collateral}/${consideration} @ ${strike} (${date})`;
}

/**
 * Fetch details + name + caller balances for a single option in one multicall.
 */
export function useOption(optionAddress: Address | undefined) {
  const { address: userAddress } = useAccount();

  const enabled = Boolean(
    optionAddress &&
      optionAddress !== "0x0" &&
      optionAddress !== "0x0000000000000000000000000000000000000000",
  );

  const address = optionAddress as Address;

  const contracts = enabled
    ? ([
        { address, abi: optionAbi, functionName: "details" as const },
        { address, abi: optionAbi, functionName: "name" as const },
        ...(userAddress
          ? ([{ address, abi: optionAbi, functionName: "balancesOf" as const, args: [userAddress] }] as const)
          : []),
      ] as const)
    : [];

  const { data, isLoading, error, refetch } = useReadContracts({
    contracts: contracts as readonly unknown[] as never,
    query: { enabled: contracts.length > 0 },
  });

  const results = data as Array<{ status: string; result?: unknown }> | undefined;
  if (!results || results.length === 0) return { data: null, isLoading, error, refetch };

  const [detailsResult, nameResult, balancesResult] = results;

  if (detailsResult?.status === "failure") {
    return { data: null, isLoading, error: new Error("Failed to fetch option details"), refetch };
  }

  const details = detailsResult?.result as OptionInfo | undefined;
  const name = nameResult?.result as string | undefined;
  const balances = balancesResult?.result as Balances | undefined;

  if (!details) return { data: null, isLoading, error, refetch };

  const optionDetails: OptionDetails = {
    ...details,
    isExpired: isExpired(details.expiration),
    balances: balances ?? null,
    formattedName: formatOptionName(name ?? ""),
  };

  return { data: optionDetails, isLoading, error, refetch };
}

export default useOption;
