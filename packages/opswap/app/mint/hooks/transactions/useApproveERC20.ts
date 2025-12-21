import { Address, erc20Abi } from "viem";
import { useWriteContract } from "wagmi";
import { MAX_UINT256 } from "../constants";

/**
 * Simple ERC20 approve transaction executor
 * Just approves token spending, nothing else
 */
export function useApproveERC20() {
  const { writeContractAsync, isPending, error } = useWriteContract();

  const approve = async (tokenAddress: Address, spenderAddress: Address) => {
    const hash = await writeContractAsync({
      address: tokenAddress,
      abi: erc20Abi,
      functionName: "approve",
      args: [spenderAddress, MAX_UINT256],
    });
    return hash;
  };

  return { approve, isPending, error };
}
