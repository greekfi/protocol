import { useQuery } from "@tanstack/react-query";
import { parseAbiItem } from "viem";
import { useChainId, usePublicClient } from "wagmi";
import deployedContracts from "~~/abi/deployedContracts";

const OPTION_CREATED_EVENT = parseAbiItem(
  "event OptionCreated(address indexed collateral, address indexed consideration, uint40 expirationDate, uint96 strike, bool isPut, bool isEuro, address oracle, address indexed option, address coll)",
);

export interface TradableOption {
  optionAddress: string;
  collateralAddress: string;
  considerationAddress: string;
  expiration: bigint;
  strike: bigint;
  isPut: boolean;
  redemptionAddress: string;
}

// Alchemy / most public RPCs cap getLogs at 10k blocks per call.
const LOG_CHUNK_SIZE = 10_000n;
const LOG_CONCURRENCY = 8;

export function useTradableOptions(underlyingToken: string | null) {
  const publicClient = usePublicClient();
  const chainId = useChainId();

  const contracts = deployedContracts[chainId as keyof typeof deployedContracts];
  const factoryAddress = contracts?.Factory?.address;
  // deploymentBlock is emitted by the ABI generator; falls back to 0 for local/anvil.
  const deploymentBlock = BigInt((contracts as { deploymentBlock?: number })?.deploymentBlock ?? 0);

  return useQuery({
    queryKey: ["tradableOptions", underlyingToken, factoryAddress, chainId],
    queryFn: async () => {
      if (!publicClient || !factoryAddress || !underlyingToken) {
        return [];
      }

      const currentBlock = await publicClient.getBlockNumber();
      const ranges: Array<{ fromBlock: bigint; toBlock: bigint }> = [];
      for (let b = deploymentBlock; b <= currentBlock; b += LOG_CHUNK_SIZE) {
        const end = b + LOG_CHUNK_SIZE - 1n > currentBlock ? currentBlock : b + LOG_CHUNK_SIZE - 1n;
        ranges.push({ fromBlock: b, toBlock: end });
      }
      const logs: Awaited<ReturnType<typeof publicClient.getLogs<typeof OPTION_CREATED_EVENT>>> = [];
      for (let i = 0; i < ranges.length; i += LOG_CONCURRENCY) {
        const batch = ranges.slice(i, i + LOG_CONCURRENCY);
        const results = await Promise.all(
          batch.map(r =>
            publicClient.getLogs({
              address: factoryAddress as `0x${string}`,
              event: OPTION_CREATED_EVENT,
              ...r,
            }),
          ),
        );
        for (const chunk of results) logs.push(...chunk);
      }

      // Filter options where the underlying token is either collateral (for calls) or consideration (for puts)
      const filtered = logs
        .filter(log => {
          const collateral = log.args.collateral?.toLowerCase();
          const consideration = log.args.consideration?.toLowerCase();
          const token = underlyingToken.toLowerCase();

          // For calls: collateral matches underlying
          // For puts: consideration matches underlying
          return collateral === token || consideration === token;
        })
        .map(log => ({
          optionAddress: log.args.option as string,
          collateralAddress: log.args.collateral as string,
          considerationAddress: log.args.consideration as string,
          expiration: BigInt(log.args.expirationDate || 0),
          strike: BigInt(log.args.strike || 0),
          isPut: log.args.isPut as boolean,
          redemptionAddress: log.args.coll as string,
        }));

      // Filter out expired options
      const now = BigInt(Math.floor(Date.now() / 1000));
      const active = filtered.filter(opt => opt.expiration > now);

      return active;
    },
    enabled: !!publicClient && !!factoryAddress && !!underlyingToken,
    staleTime: 30_000, // 30 seconds
    refetchInterval: 30_000, // Refetch every 30 seconds
  });
}
