import { useMemo, useCallback } from "react";
import { Address, parseAbiItem } from "viem";
import { usePublicClient, useReadContracts } from "wagmi";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { useOptionFactoryContract } from "./useContracts";
import type { OptionListItem } from "./types";

// Event signature for OptionCreated
const OPTION_CREATED_EVENT = parseAbiItem(
  "event OptionCreated(address collateral, address consideration, uint256 expirationDate, uint256 strike, bool isPut, address option, address redemption)"
);

// Simple ERC20 name ABI
const NAME_ABI = [
  {
    type: "function",
    name: "name",
    inputs: [],
    outputs: [{ type: "string", name: "" }],
    stateMutability: "view",
  },
] as const;

/**
 * Hook to fetch all created options from factory events
 * Uses TanStack Query for caching and the factory's OptionCreated events
 *
 * @returns List of all created options with their metadata
 */
export function useOptions() {
  const publicClient = usePublicClient();
  const factory = useOptionFactoryContract();
  const queryClient = useQueryClient();

  const factoryAddress = factory?.address as Address | undefined;

  // Fetch OptionCreated events using TanStack Query
  const {
    data: eventData = [],
    isLoading: isLoadingEvents,
    error: eventsError,
  } = useQuery({
    queryKey: ["optionCreatedEvents", factoryAddress],
    queryFn: async () => {
      if (!publicClient || !factoryAddress) return [];

      const logs = await publicClient.getLogs({
        address: factoryAddress,
        event: OPTION_CREATED_EVENT,
        fromBlock: 0n,
        toBlock: "latest",
      });

      return logs.map((log) => ({
        address: log.args.option as Address,
        collateral: log.args.collateral as Address,
        consideration: log.args.consideration as Address,
        expiration: log.args.expirationDate as bigint,
        strike: log.args.strike as bigint,
        isPut: log.args.isPut as boolean,
      }));
    },
    enabled: Boolean(publicClient && factoryAddress),
    staleTime: 30_000, // Cache for 30 seconds
    refetchOnWindowFocus: false,
  });

  // Build contracts array for batch name fetching
  const nameContracts = useMemo(
    () =>
      eventData.map((opt) => ({
        address: opt.address,
        abi: NAME_ABI,
        functionName: "name" as const,
      })),
    [eventData]
  );

  // Batch fetch names for all options
  const { data: namesData, isLoading: isLoadingNames } = useReadContracts({
    contracts: nameContracts,
    query: {
      enabled: nameContracts.length > 0,
    },
  });

  // Combine event data with names
  const options: OptionListItem[] = useMemo(
    () =>
      eventData.map((opt, idx) => ({
        ...opt,
        name: (namesData?.[idx]?.result as string) ?? `Option ${opt.address.slice(0, 10)}...`,
      })),
    [eventData, namesData]
  );

  // Refetch function that invalidates the query cache
  const refetch = useCallback(() => {
    queryClient.invalidateQueries({
      queryKey: ["optionCreatedEvents", factoryAddress],
    });
  }, [queryClient, factoryAddress]);

  // Convert options to the format expected by SelectOptionAddress
  const optionList = options.map((opt) => ({
    name: opt.name,
    address: opt.address,
  }));

  return {
    options,
    optionList,
    isLoading: isLoadingEvents || isLoadingNames,
    error: eventsError,
    refetch,
  };
}

export default useOptions;
