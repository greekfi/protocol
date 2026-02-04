// @ts-nocheck
import { ADDRESS } from "./constants";
import { useChainId } from "wagmi";

export const useAddress = () => {
  const chainId = useChainId();
  return ADDRESS[chainId as keyof typeof ADDRESS];
};
