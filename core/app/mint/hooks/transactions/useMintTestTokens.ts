import { useMemo } from "react";
import { useContracts } from "../useContracts";
import { Address, erc20Abi } from "viem";
import { useAccount, useChainId, useReadContracts, useWriteContract } from "wagmi";

/**
 * Hook to mint test tokens on localhost.
 *
 * Discovers every test-token contract that was actually deployed to this chain:
 *   - StableToken / ShakyToken (from DeployOp)
 *   - Every MockERC20.addresses[] entry (from DeployFullDemo)
 *
 * Reads each token's decimals on-chain so the minted amount is always
 * `amount * 10^decimals` regardless of whether the token is 6, 8, or 18-dec.
 */
const MINT_ABI = [
  {
    type: "function",
    name: "mint",
    inputs: [
      { name: "to", type: "address" },
      { name: "amount", type: "uint256" },
    ],
    outputs: [],
    stateMutability: "nonpayable",
  },
] as const;

export function useMintTestTokens() {
  const { writeContractAsync, isPending, error } = useWriteContract();
  const { address } = useAccount();
  const chainId = useChainId();
  const contracts = useContracts();

  const isLocalhost = chainId === 31337;

  const tokenAddresses: Address[] = useMemo(() => {
    if (!contracts) return [];
    const addrs: Address[] = [];
    const stable = (contracts as { StableToken?: { address: Address } }).StableToken?.address;
    const shaky = (contracts as { ShakyToken?: { address: Address } }).ShakyToken?.address;
    const mocks = (contracts as { MockERC20?: { addresses?: Address[] } }).MockERC20?.addresses ?? [];
    if (stable) addrs.push(stable);
    if (shaky) addrs.push(shaky);
    for (const a of mocks) if (!addrs.includes(a)) addrs.push(a);
    return addrs;
  }, [contracts]);

  // Batch-read decimals + symbol for every discovered token
  const { data: tokenMeta } = useReadContracts({
    contracts: tokenAddresses.flatMap(addr => [
      { address: addr, abi: erc20Abi, functionName: "decimals" as const },
      { address: addr, abi: erc20Abi, functionName: "symbol" as const },
    ]),
    query: { enabled: isLocalhost && tokenAddresses.length > 0 },
  });

  const tokens = useMemo(
    () =>
      tokenAddresses.map((addr, i) => ({
        address: addr,
        decimals: (tokenMeta?.[i * 2]?.result as number | undefined) ?? 18,
        symbol: (tokenMeta?.[i * 2 + 1]?.result as string | undefined) ?? "TOKEN",
      })),
    [tokenAddresses, tokenMeta],
  );

  const mintTokens = async (amount = 1000n): Promise<`0x${string}`[]> => {
    if (!address) throw new Error("No wallet connected");
    if (!isLocalhost) throw new Error("Faucet only available on localhost");
    if (tokens.length === 0) throw new Error("No test tokens found on this chain");

    const hashes: `0x${string}`[] = [];
    for (const t of tokens) {
      const hash = await writeContractAsync({
        address: t.address,
        abi: MINT_ABI,
        functionName: "mint",
        args: [address, amount * 10n ** BigInt(t.decimals)],
      });
      hashes.push(hash);
      // small pacing to avoid nonce races
      await new Promise(r => setTimeout(r, 50));
    }
    return hashes;
  };

  return {
    mintTokens,
    isPending,
    error,
    isLocalhost,
    tokens,
  };
}
