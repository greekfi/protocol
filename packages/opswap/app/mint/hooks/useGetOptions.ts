import { useContract } from "./useContract";
import { Address, erc20Abi, parseAbiItem } from "viem";
import { useReadContracts, usePublicClient } from "wagmi";
import { useEffect, useState, useMemo, useCallback, useRef } from "react";

export const useGetOptions = () => {
  const contract = useContract();
  const publicClient = usePublicClient();
  const [createdOptions, setCreatedOptions] = useState<Address[]>([]);
  const [isLoadingEvents, setIsLoadingEvents] = useState(true);
  const [error, setError] = useState<Error | null>(null);

  const factoryAddress = contract?.OptionFactory?.address;

  // Query OptionCreated events to get all created options - ONLY ONCE ON MOUNT
  useEffect(() => {
    const fetchEvents = async () => {
      if (!publicClient || !factoryAddress) {
        setIsLoadingEvents(false);
        return;
      }

      try {
        setIsLoadingEvents(true);
        const logs = await publicClient.getLogs({
          address: factoryAddress as Address,
          event: parseAbiItem("event OptionCreated(address collateral, address consideration, uint256 expirationDate, uint256 strike, bool isPut, address option, address redemption)"),
          fromBlock: 0n,
          toBlock: "latest",
        });

        const optionAddresses = logs.map((log) => log.args.option as Address);
        setCreatedOptions(optionAddresses);
        setError(null);
      } catch (err) {
        console.error("Error fetching OptionCreated events:", err);
        setError(err as Error);
      } finally {
        setIsLoadingEvents(false);
      }
    };

    fetchEvents();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []); // Empty deps - run ONCE on mount only

  // Memoize contracts array to prevent recreation on every render
  const contracts = useMemo(
    () =>
      createdOptions.map((option: Address) => ({
        address: option,
        abi: erc20Abi,
        functionName: "name" as const,
      })),
    [createdOptions]
  );

  const {
    data: allOptions,
    error: error_,
    refetch: refetchNames,
  } = useReadContracts({
    contracts,
    query: {
      enabled: createdOptions.length > 0,
    },
  });

  // Memoize optionList to prevent recreation on every render
  const optionList = useMemo(
    () =>
      (allOptions || []).map((option: any, index: number) => ({
        name: option.result as string,
        address: createdOptions[index],
      })),
    [allOptions, createdOptions]
  );

  // Memoize refetchAll function
  const refetchAll = useCallback(async () => {
    // Refetch events
    if (!publicClient || !factoryAddress) return;

    try {
      const logs = await publicClient.getLogs({
        address: factoryAddress as Address,
        event: parseAbiItem("event OptionCreated(address collateral, address consideration, uint256 expirationDate, uint256 strike, bool isPut, address option, address redemption)"),
        fromBlock: 0n,
        toBlock: "latest",
      });

      const optionAddresses = logs.map((log) => log.args.option as Address);
      setCreatedOptions(optionAddresses);
    } catch (err) {
      console.error("Error refetching events:", err);
    }

    // Refetch names
    if (refetchNames) {
      refetchNames();
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []); // Empty deps - stable function reference

  // Use ref to keep stable return object
  const returnValueRef = useRef({
    createdOptions: [] as Address[],
    allOptions: undefined as any,
    optionList: [] as any[],
    error: undefined as any,
    refetch: refetchAll,
    isLoading: true,
  });

  // Only update if values actually changed
  if (
    createdOptions !== returnValueRef.current.createdOptions ||
    optionList !== returnValueRef.current.optionList ||
    isLoadingEvents !== returnValueRef.current.isLoading
  ) {
    returnValueRef.current = {
      createdOptions,
      allOptions,
      optionList,
      error: error_,
      refetch: refetchAll,
      isLoading: isLoadingEvents,
    };
  }

  return returnValueRef.current;
};
