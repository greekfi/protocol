import { useCallback, useMemo } from "react";
import type { OptionListItem } from "./types";
import { useReadContracts } from "wagmi";
import { useBrowseChainId } from "../../hooks/useBrowseChain";
import { useQueryClient } from "@tanstack/react-query";
import { Address } from "viem";
import { optionAbi } from "~~/generated";
import { useChainEvents, type OptionCreatedEvent } from "../../hooks/useChainEvents";

export function useOptions() {
  const chainId = useBrowseChainId();
  const queryClient = useQueryClient();

  const {
    data: events = [],
    isLoading: isLoadingEvents,
    error: eventsError,
  } = useChainEvents(chainId);

  // Map the events-API shape to the legacy OptionListItem shape used by /mint.
  const eventData = useMemo(
    () =>
      events.map((e: OptionCreatedEvent) => ({
        address: e.args.option as Address,
        collateral: e.args.collateral as Address,
        consideration: e.args.consideration as Address,
        expiration: BigInt(e.args.expirationDate),
        strike: BigInt(e.args.strike),
        isPut: e.args.isPut,
        receipt: e.args.receipt as Address,
      })),
    [events],
  );

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
    queryClient.invalidateQueries({ queryKey: ["chainEvents"] });
  }, [queryClient]);

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
