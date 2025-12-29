// @ts-nocheck
import {useContract} from "./useContract";
import {useWriteContract} from "wagmi";
import {useAddress} from "./useAddress";

export const useAddOption = () => {
  const contract = useContract();
  const { data: result, writeContractAsync } = useWriteContract();
  const address = useAddress();

  return async (optionAddress: string) => {

      console.log("Add OptionAddress:", optionAddress);
      const result_ = await writeContractAsync({
          address: contract?.OpHook.address as `0x${string}`,
          abi: contract?.OpHook.abi,
          functionName: "initPool",
          args: [optionAddress as `0x${string}`, address.tokens.usdc.address, address.tokens.weth.address, address.pricePools.weth, 0],
      });
      console.log("Add Option Result:", result_);
      console.log("Add Option Result:", result);
  };
};
