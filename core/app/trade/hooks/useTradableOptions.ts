import { useQuery } from "@tanstack/react-query";
import { parseAbiItem } from "viem";
import { useChainId, usePublicClient } from "wagmi";
import deployedContracts from "~~/contracts/deployedContracts";

const OPTION_CREATED_EVENT = parseAbiItem(
  "event OptionCreated(address indexed collateral, address indexed consideration, uint40 expirationDate, uint96 strike, bool isPut, address indexed option, address redemption)",
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

export function useTradableOptions(underlyingToken: string | null) {
  const publicClient = usePublicClient();
  const chainId = useChainId();

  const contracts = deployedContracts[chainId as keyof typeof deployedContracts];
  const factoryAddress = contracts?.OptionFactory?.address;
  // const factoryAddress = "0xeac6035621817b16811395f1f1fa3e3705b0aacd";
  // Use earliest block to fetch all events
  const deploymentBlock = 0n;

  return useQuery({
    queryKey: ["tradableOptions", underlyingToken, factoryAddress, chainId],
    queryFn: async () => {
      if (!publicClient || !factoryAddress || !underlyingToken) {
        return [];
      }

      // Fetch all OptionCreated events
      const logs = await publicClient.getLogs({
        address: factoryAddress as `0x${string}`,
        event: OPTION_CREATED_EVENT,
        fromBlock: BigInt(deploymentBlock),
        toBlock: "latest",
      });

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
          redemptionAddress: log.args.redemption as string,
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
