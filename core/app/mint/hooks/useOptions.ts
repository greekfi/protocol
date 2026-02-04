import { useCallback, useMemo } from "react";
import type { OptionListItem } from "./types";
import { useContracts } from "./useContracts";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { Address, parseAbiItem } from "viem";
import { usePublicClient, useReadContracts } from "wagmi";

// Event signature for OptionCreated
const OPTION_CREATED_EVENT = parseAbiItem(
  "event OptionCreated(address indexed collateral, address indexed consideration, uint40 expirationDate, uint96 strike, bool isPut, address indexed option, address redemption)",
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
  const contracts = useContracts();
  const queryClient = useQueryClient();

  const factoryAddress = contracts?.OptionFactory?.address as Address | undefined;
  const deploymentBlock = (contracts as { deploymentBlock?: number })?.deploymentBlock ?? 0;
  const chainId = (contracts as { chainId?: number })?.chainId;

  // Fetch OptionCreated events using TanStack Query
  const {
    data: eventData = [],
    isLoading: isLoadingEvents,
    error: eventsError,
  } = useQuery({
    queryKey: ["optionCreatedEvents", factoryAddress, chainId, deploymentBlock],
    queryFn: async () => {
      if (!publicClient || !factoryAddress) return [];

      // Use deployment block from contracts config (extracted from broadcast receipts)
      const fromBlock = BigInt(deploymentBlock);

      console.log("Fetching OptionCreated events:", {
        chainId,
        factoryAddress,
        deploymentBlock,
        fromBlock: fromBlock.toString(),
      });

      const logs = await publicClient.getLogs({
        address: factoryAddress,
        event: OPTION_CREATED_EVENT,
        fromBlock,
        toBlock: "latest",
      });

      console.log(`Found ${logs.length} OptionCreated events`);

      return logs.map(log => ({
        address: log.args.option as Address,
        collateral: log.args.collateral as Address,
        consideration: log.args.consideration as Address,
        expiration: BigInt(log.args.expirationDate ?? 0),
        strike: BigInt(log.args.strike ?? 0),
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
      eventData.map(opt => ({
        address: opt.address,
        abi: NAME_ABI,
        functionName: "name" as const,
      })),
    [eventData],
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
    [eventData, namesData],
  );

  // Refetch function that invalidates the query cache
  const refetch = useCallback(() => {
    queryClient.invalidateQueries({
      queryKey: ["optionCreatedEvents", factoryAddress],
    });
  }, [queryClient, factoryAddress]);

  // Convert options to the format expected by SelectOptionAddress
  const optionList = options.map(opt => ({
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
