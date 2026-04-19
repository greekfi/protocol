import { MAX_UINT256 } from "../constants";
import { Address, erc20Abi } from "viem";
import { useWriteContract } from "wagmi";

/**
 * Simple ERC20 approve transaction executor
 * Just approves token spending, nothing else
 */
export function useApproveERC20() {
  const { writeContractAsync, isPending, error } = useWriteContract();

  const approve = async (tokenAddress: Address, spenderAddress: Address) => {
    console.log("useApproveERC20.approve called");
    console.log("  tokenAddress:", tokenAddress);
    console.log("  spenderAddress:", spenderAddress);
    console.log("  MAX_UINT256:", MAX_UINT256.toString());

    try {
      const hash = await writeContractAsync({
        address: tokenAddress,
        abi: erc20Abi,
        functionName: "approve",
        args: [spenderAddress, MAX_UINT256],
      });
      console.log("  Success! Hash:", hash);
      return hash;
    } catch (err: any) {
      console.error("  writeContractAsync error:", err);
      console.error("  Error message:", err.message);
      console.error("  Error code:", err.code);
      throw err;
    }
  };

  return { approve, isPending, error };
}
