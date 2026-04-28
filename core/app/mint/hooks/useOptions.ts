import { useCallback, useMemo } from "react";
import type { OptionListItem } from "./types";
import { useContracts } from "./useContracts";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { Address } from "viem";
import { usePublicClient, useReadContracts } from "wagmi";
import { factoryAbi, optionAbi } from "~~/generated";

// Pull the OptionCreated event definition straight from the generated ABI so
// the topic0 hash can never drift from the contract.
const OPTION_CREATED_EVENT = factoryAbi.find(
  e => e.type === "event" && e.name === "OptionCreated",
) as Extract<(typeof factoryAbi)[number], { type: "event"; name: "OptionCreated" }>;

// Alchemy / most public RPCs cap getLogs at 10k blocks per call.
const LOG_CHUNK_SIZE = 10_000n;
const LOG_CONCURRENCY = 8;

export function useOptions() {
  const publicClient = usePublicClient();
  const contracts = useContracts();
  const queryClient = useQueryClient();

  const factoryAddress = contracts?.Factory?.address as Address | undefined;
  const deploymentBlock = (contracts as { deploymentBlock?: number })?.deploymentBlock ?? 0;
  const chainId = (contracts as { chainId?: number })?.chainId;

  const {
    data: eventData = [],
    isLoading: isLoadingEvents,
    error: eventsError,
  } = useQuery({
    queryKey: ["optionCreatedEvents", factoryAddress, chainId, deploymentBlock],
    queryFn: async () => {
      if (!publicClient || !factoryAddress) return [];

      const currentBlock = await publicClient.getBlockNumber();
      // Scan from deploymentBlock through current — matches useTradableOptions on
      // /trade and /yield. The previous 500k-block cap was hiding any option older
      // than ~12 days on Base (and similarly on the other chains), so /mint would
      // come up empty even though the options exist on-chain.
      const fromBlock = BigInt(deploymentBlock);

      const ranges: Array<{ fromBlock: bigint; toBlock: bigint }> = [];
      for (let b = fromBlock; b <= currentBlock; b += LOG_CHUNK_SIZE) {
        const end = b + LOG_CHUNK_SIZE - 1n > currentBlock ? currentBlock : b + LOG_CHUNK_SIZE - 1n;
        ranges.push({ fromBlock: b, toBlock: end });
      }
      console.log(
        `[useOptions] chain=${chainId} factory=${factoryAddress} scan=${fromBlock}→${currentBlock} chunks=${ranges.length}`,
      );

      const logs: Awaited<ReturnType<typeof publicClient.getLogs<typeof OPTION_CREATED_EVENT>>> = [];
      for (let i = 0; i < ranges.length; i += LOG_CONCURRENCY) {
        const batch = ranges.slice(i, i + LOG_CONCURRENCY);
        const results = await Promise.all(
          batch.map(r => publicClient.getLogs({ address: factoryAddress, event: OPTION_CREATED_EVENT, ...r })),
        );
        for (const chunk of results) logs.push(...chunk);
      }
      console.log(`[useOptions] found ${logs.length} OptionCreated events`);

      return logs.map(log => ({
        address: log.args.option as Address,
        collateral: log.args.collateral as Address,
        consideration: log.args.consideration as Address,
        expiration: BigInt(log.args.expirationDate ?? 0),
        strike: BigInt(log.args.strike ?? 0),
        isPut: log.args.isPut as boolean,
        coll: log.args.coll as Address,
      }));
    },
    enabled: Boolean(publicClient && factoryAddress),
    staleTime: 30_000,
    refetchOnWindowFocus: false,
  });

  const nameContracts = useMemo(
    () =>
      eventData.map(opt => ({
        address: opt.address,
        abi: optionAbi,
        functionName: "name" as const,
      })),
    [eventData],
  );

  const { data: namesData, isLoading: isLoadingNames } = useReadContracts({
    contracts: nameContracts,
    query: { enabled: nameContracts.length > 0 },
  });

  const options: OptionListItem[] = useMemo(
    () =>
      eventData.map((opt, idx) => ({
        ...opt,
        name: (namesData?.[idx]?.result as string | undefined) ?? `Option ${opt.address.slice(0, 10)}...`,
      })),
    [eventData, namesData],
  );

  const refetch = useCallback(() => {
    queryClient.invalidateQueries({ queryKey: ["optionCreatedEvents", factoryAddress] });
  }, [queryClient, factoryAddress]);

  const optionList = options.map(opt => ({ name: opt.name, address: opt.address }));

  return {
    options,
    optionList,
    isLoading: isLoadingEvents || isLoadingNames,
    error: eventsError,
    refetch,
  };
}

export default useOptions;
