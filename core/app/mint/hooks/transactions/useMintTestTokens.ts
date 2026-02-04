import { useContracts } from "../useContracts";
import { Address } from "viem";
import { useAccount, useChainId, useWriteContract } from "wagmi";

/**
 * Hook to mint test tokens (StableToken and ShakyToken) on localhost
 * Mints 1000 tokens of each to the connected wallet
 */
export function useMintTestTokens() {
  const { writeContractAsync, isPending, error } = useWriteContract();
  const { address } = useAccount();
  const chainId = useChainId();
  const contracts = useContracts();

  // Only available on localhost (chainId 31337)
  const isLocalhost = chainId === 31337;

  const mintTokens = async (amountPerToken: bigint = 1000n * 10n ** 18n): Promise<`0x${string}`[]> => {
    if (!address) throw new Error("No wallet connected");
    if (!isLocalhost) throw new Error("Faucet only available on localhost");
    if (!contracts?.StableToken || !contracts?.ShakyToken) {
      throw new Error("Test tokens not deployed");
    }

    const hashes: `0x${string}`[] = [];

    // Mint StableToken
    const stableHash = await writeContractAsync({
      address: contracts.StableToken.address as Address,
      abi: contracts.StableToken.abi,
      functionName: "mint",
      args: [address, amountPerToken],
    });
    hashes.push(stableHash);

    // Wait a bit to avoid nonce issues
    await new Promise(resolve => setTimeout(resolve, 100));

    // Mint ShakyToken
    const shakyHash = await writeContractAsync({
      address: contracts.ShakyToken.address as Address,
      abi: contracts.ShakyToken.abi,
      functionName: "mint",
      args: [address, amountPerToken],
    });
    hashes.push(shakyHash);

    return hashes;
  };

  return {
    mintTokens,
    isPending,
    error,
    isLocalhost,
    stableTokenAddress: contracts?.StableToken?.address,
    shakyTokenAddress: contracts?.ShakyToken?.address,
  };
}
