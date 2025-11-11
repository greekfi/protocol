import { useChainId } from "wagmi";
import { ADDRESS } from "./constants";

export const useAddress = () => {
  const chainId = useChainId();
  return ADDRESS[chainId as keyof typeof ADDRESS];
};
