import { useCallback, useState } from "react";
import { Address, erc20Abi } from "viem";
import { useWriteContract, useWaitForTransactionReceipt } from "wagmi";
import { useFactoryAddress, useOptionFactoryContract } from "./useContracts";
import { MAX_UINT256 } from "./constants";

interface UseApproveReturn {
  /** Approve ERC20 token to factory */
  approveErc20: (tokenAddress: Address) => Promise<`0x${string}` | null>;
  /** Approve factory for token */
  approveFactory: (tokenAddress: Address) => Promise<`0x${string}` | null>;
  /** Whether approval transaction is pending */
  isPending: boolean;
  /** Last transaction hash */
  txHash: `0x${string}` | null;
  /** Error if any */
  error: Error | null;
}

/**
 * Simple hook to execute approval transactions
 * Does NOT check allowances - that's the application's responsibility
 *
 * Usage:
 * 1. Application checks allowances via useAllowances
 * 2. Application decides which approvals are needed
 * 3. Application calls approveErc20() or approveFactory() as needed
 * 4. Application waits for confirmation
 */
export function useApprove(): UseApproveReturn {
  const [txHash, setTxHash] = useState<`0x${string}` | null>(null);
  const [error, setError] = useState<Error | null>(null);

  const factoryAddress = useFactoryAddress();
  const factoryContract = useOptionFactoryContract();
  const { writeContractAsync, isPending } = useWriteContract();

  const approveErc20 = useCallback(
    async (tokenAddress: Address): Promise<`0x${string}` | null> => {
      if (!factoryAddress) {
        const err = new Error("Factory address not available");
        setError(err);
        throw err;
      }

      try {
        setError(null);
        const hash = await writeContractAsync({
          address: tokenAddress,
          abi: erc20Abi,
          functionName: "approve",
          args: [factoryAddress, MAX_UINT256],
        });
        setTxHash(hash);
        return hash;
      } catch (err) {
        setError(err as Error);
        throw err;
      }
    },
    [factoryAddress, writeContractAsync]
  );

  const approveFactory = useCallback(
    async (tokenAddress: Address): Promise<`0x${string}` | null> => {
      if (!factoryAddress || !factoryContract?.abi) {
        const err = new Error("Factory not available");
        setError(err);
        throw err;
      }

      try {
        setError(null);
        const hash = await writeContractAsync({
          address: factoryAddress,
          abi: factoryContract.abi as readonly unknown[],
          functionName: "approve",
          args: [tokenAddress, MAX_UINT256],
        });
        setTxHash(hash);
        return hash;
      } catch (err) {
        setError(err as Error);
        throw err;
      }
    },
    [factoryAddress, factoryContract, writeContractAsync]
  );

  return {
    approveErc20,
    approveFactory,
    isPending,
    txHash,
    error,
  };
}

export default useApprove;
