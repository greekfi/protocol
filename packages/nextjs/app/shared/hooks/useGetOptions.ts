import { useContract } from "./useContract";
import { Address, erc20Abi } from "viem";
import { useReadContract, useReadContracts } from "wagmi";

export const useGetOptions = () => {
  const contract = useContract();
  const abi = contract?.OptionFactory?.abi;

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

  console.log("createdOptions", createdOptions);
  console.log("error", error);

  const {
    data: allOptions,
    error: error_,
    refetch: refetchNames,
  } = useReadContracts({
    contracts: ((createdOptions as Address[]) || [])
      .map((option: Address) =>
        option
          ? {
              address: option,
              abi: erc20Abi,
              functionName: "name",
            }
          : undefined,
      )
      .filter(option => option !== undefined),
    query: {
      enabled: !!createdOptions,
    },
  });

  const optionList = (allOptions || []).map((option, index) => ({
    name: option.result as string,
    address: ((createdOptions as Address[]) || [])[index],
  }));

  const refetchAll = () => {
    refetch();
    refetchNames();
  };

  return {
    createdOptions,
    allOptions,
    optionList,
    error: error_,
    refetch: refetchAll,
  };
};
