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
// Cap the scan window to avoid 1000+ chunks on fast-block chains like Arbitrum.
// 500k blocks ≈ 35h on Arbitrum (~0.25s/block) / weeks on mainnet (~12s/block).
const MAX_SCAN_WINDOW = 500_000n;

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
      const windowStart = currentBlock > MAX_SCAN_WINDOW ? currentBlock - MAX_SCAN_WINDOW : 0n;
      const fromBlock = deploymentBlock > windowStart ? deploymentBlock : windowStart;
      const ranges: Array<{ fromBlock: bigint; toBlock: bigint }> = [];
      for (let b = fromBlock; b <= currentBlock; b += LOG_CHUNK_SIZE) {
        const end = b + LOG_CHUNK_SIZE - 1n > currentBlock ? currentBlock : b + LOG_CHUNK_SIZE - 1n;
        ranges.push({ fromBlock: b, toBlock: end });
      }
      console.log(
        `[useTradableOptions] chain=${chainId} factory=${factoryAddress} underlying=${underlyingToken} scan=${fromBlock}→${currentBlock} chunks=${ranges.length}`,
      );
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
      console.log(
        `[useTradableOptions] found ${logs.length} events, ${filtered.length} match underlying, ${active.length} active`,
      );

      return active;
    },
    enabled: !!publicClient && !!factoryAddress && !!underlyingToken,
    staleTime: 30_000, // 30 seconds
    refetchInterval: 30_000, // Refetch every 30 seconds
  });
}
