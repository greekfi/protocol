import { PERMIT2_ADDRESS } from "@uniswap/permit2-sdk";
import { erc20Abi } from "viem";
import { Address } from "viem";
import { useAccount, useReadContract } from "wagmi";

export const useAllowanceCheck = (considerationAddress: Address, collateralAddress: Address) => {
  const { address } = useAccount();

  const { data: considerationAllowance } = useReadContract({
    address: considerationAddress,
    abi: erc20Abi,
    functionName: "allowance",
    args: [address as Address, PERMIT2_ADDRESS],
  });
  const { data: collateralAllowance } = useReadContract({
    address: collateralAddress,
    abi: erc20Abi,
    functionName: "allowance",
    args: [address as Address, PERMIT2_ADDRESS],
  });

  return { considerationAllowance, collateralAllowance };
};
