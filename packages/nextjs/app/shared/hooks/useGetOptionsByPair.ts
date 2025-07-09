import { useContract } from "./useContract";
import { Address, erc20Abi } from "viem";
import { useReadContract, useReadContracts } from "wagmi";

export interface OptionData {
  address: Address;
  name: string;
  expirationDate: bigint;
  strike: bigint;
  isPut: boolean;
  collateralAddress: Address;
  considerationAddress: Address;
  collateralName: string;
  considerationName: string;
}

export interface ExpirationGroup {
  expirationDate: bigint;
  formattedDate: string;
  options: OptionData[];
}

export const useGetOptionsByPair = (collateralAddress?: Address, considerationAddress?: Address) => {
  const contract = useContract();
  const abi = contract?.OptionFactory?.abi;
  const longOptionAbi = contract?.LongOption?.abi;

  // Get all created options
  const {
    data: createdOptions,
    error,
    refetch,
  } = useReadContract({
    address: contract?.OptionFactory?.address,
    abi,
    functionName: "getCreatedOptions",
    query: {
      enabled: !!contract?.OptionFactory?.address,
    },
  });

  // Fetch details for all options
  const optionContracts = ((createdOptions as Address[]) || []).map(address => ({
    address,
    abi: longOptionAbi,
    functionName: "collateral" as const,
  }));

  const { data: collateralAddresses, error: collateralError } = useReadContracts({
    contracts: optionContracts,
    query: {
      enabled: !!createdOptions && createdOptions.length > 0,
    },
  });

  const considerationContracts = ((createdOptions as Address[]) || []).map(address => ({
    address,
    abi: longOptionAbi,
    functionName: "consideration" as const,
  }));

  const { data: considerationAddresses, error: considerationError } = useReadContracts({
    contracts: considerationContracts,
    query: {
      enabled: !!createdOptions && createdOptions.length > 0,
    },
  });

  const expirationContracts = ((createdOptions as Address[]) || []).map(address => ({
    address,
    abi: longOptionAbi,
    functionName: "expirationDate" as const,
  }));

  const { data: expirationDates, error: expirationError } = useReadContracts({
    contracts: expirationContracts,
    query: {
      enabled: !!createdOptions && createdOptions.length > 0,
    },
  });

  const strikeContracts = ((createdOptions as Address[]) || []).map(address => ({
    address,
    abi: longOptionAbi,
    functionName: "strike" as const,
  }));

  const { data: strikes, error: strikeError } = useReadContracts({
    contracts: strikeContracts,
    query: {
      enabled: !!createdOptions && createdOptions.length > 0,
    },
  });

  const isPutContracts = ((createdOptions as Address[]) || []).map(address => ({
    address,
    abi: longOptionAbi,
    functionName: "isPut" as const,
  }));

  const { data: isPuts, error: isPutError } = useReadContracts({
    contracts: isPutContracts,
    query: {
      enabled: !!createdOptions && createdOptions.length > 0,
    },
  });

  const nameContracts = ((createdOptions as Address[]) || []).map(address => ({
    address,
    abi: erc20Abi,
    functionName: "name" as const,
  }));

  const { data: names, error: nameError } = useReadContracts({
    contracts: nameContracts,
    query: {
      enabled: !!createdOptions && createdOptions.length > 0,
    },
  });

  // Filter options by pair if specified
  const filteredOptions: OptionData[] = [];

  if (
    createdOptions &&
    collateralAddresses &&
    considerationAddresses &&
    expirationDates &&
    strikes &&
    isPuts &&
    names
  ) {
    for (let i = 0; i < createdOptions.length; i++) {
      const optionAddress = createdOptions[i] as Address;
      const optionCollateral = collateralAddresses[i]?.result as Address;
      const optionConsideration = considerationAddresses[i]?.result as Address;

      // Filter by pair if specified
      if (collateralAddress && considerationAddress) {
        if (optionCollateral !== collateralAddress || optionConsideration !== considerationAddress) {
          continue;
        }
      }

      filteredOptions.push({
        address: optionAddress,
        name: names[i]?.result as string,
        expirationDate: expirationDates[i]?.result as bigint,
        strike: strikes[i]?.result as bigint,
        isPut: isPuts[i]?.result as boolean,
        collateralAddress: optionCollateral,
        considerationAddress: optionConsideration,
        collateralName: "", // Will be filled later
        considerationName: "", // Will be filled later
      });
    }
  }

  // Group by expiration date
  const expirationGroups: ExpirationGroup[] = [];
  const groupedByExpiration = new Map<string, OptionData[]>();

  filteredOptions.forEach(option => {
    const expirationKey = option.expirationDate.toString();
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
    error: error || collateralError || considerationError || expirationError || strikeError || isPutError || nameError,
    refetch,
  };
};
