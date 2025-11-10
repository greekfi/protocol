import { useContract } from "./useContract";
import { useWriteContract } from "wagmi";
import {ADDRESS } from "./constants";
import { useAddress } from "./useAddress";

export const useAddOption = () => {
  const contract = useContract();
  const { data: result, writeContractAsync } = useWriteContract();


            // {
            //   name: "optionToken",
            //   type: "address",
            //   internalType: "address",
            // },
            // {
            //   name: "cashToken",
            //   type: "address",
            //   internalType: "address",
            // },
            // {
            //   name: "collateral",
            //   type: "address",
            //   internalType: "address",
            // },
            // {
            //   name: "pricePool",
            //   type: "address",
            //   internalType: "address",
            // },
            // {
            //   name: "fee",
            //   type: "uint24",
            //   internalType: "uint24",
            // },

  const addOptions = async (optionAddress: string) => {
    const address = useAddress();
    
    console.log("Add OptionAddress:", optionAddress);
    const result_ = await writeContractAsync({
      address: contract?.OpHook.address as `0x${string}`,
      abi: contract?.OpHook.abi,
      functionName: "initPool",
      args: [optionAddress as `0x${string}`,  address.tokens.usdc.address, address.tokens.weth.address, address.pricePools.weth, 0],
    });
    console.log("Add Option Result:", result_);
    console.log("Add Option Result:", result);
  };

  return addOptions;
};
