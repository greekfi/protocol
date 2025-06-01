import { useChainStore } from "./config";
import { createPublicClient, http } from "viem";

export const getPublicClient = () => {
  const { currentChain } = useChainStore.getState();

  return createPublicClient({
    chain: currentChain,
    transport: http(),
  });
};

export const publicClient = getPublicClient();
