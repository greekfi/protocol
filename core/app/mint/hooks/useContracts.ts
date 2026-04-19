import { useChainId } from "wagmi";
import deployedContracts from "~~/abi/deployedContracts";

export function useContracts() {
  const chainId = useChainId();
  return deployedContracts[chainId as keyof typeof deployedContracts];
}
