import { useMemo } from "react";
import { useChainId } from "wagmi";
import deployedContracts from "~~/contracts/deployedContracts";

export const useContract = () => {
  const chainId = useChainId();

  const contract = useMemo(() => {
    const contracts = deployedContracts[chainId as keyof typeof deployedContracts];
    if (!contracts) {
      console.warn(`No contracts found for chain ID ${chainId}`);
    }
    return contracts;
  }, [chainId]);

  return contract;
};
