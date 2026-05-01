import { useMemo } from "react";
import type { OptionListItem } from "./types";
import { erc20Abi } from "viem";
import { useAccount, useReadContracts } from "wagmi";

export interface OptionWithBalances extends OptionListItem {
  optionBalance: bigint;
  receiptBalance: bigint;
}

/**
 * Batch-reads the connected user's balanceOf for each option's long (option)
 * and short (receipt) token. Returns only those where at least one is nonzero.
 */
export function useMyOptionBalances(options: OptionListItem[]) {
  const { address } = useAccount();

  const contracts = useMemo(() => {
    if (!address) return [];
    return options.flatMap(opt => [
      {
        address: opt.address,
        abi: erc20Abi,
        functionName: "balanceOf" as const,
        args: [address] as const,
      },
      {
        address: opt.receipt,
        abi: erc20Abi,
        functionName: "balanceOf" as const,
        args: [address] as const,
      },
    ]);
  }, [address, options]);

  const { data, isLoading, refetch } = useReadContracts({
    contracts,
    query: { enabled: contracts.length > 0, refetchOnWindowFocus: false },
  });

  const held: OptionWithBalances[] = useMemo(() => {
    if (!data) return [];
    const results: OptionWithBalances[] = [];
    options.forEach((opt, i) => {
      const optionBal = (data[i * 2]?.result as bigint | undefined) ?? 0n;
      const receiptBal = (data[i * 2 + 1]?.result as bigint | undefined) ?? 0n;
      if (optionBal > 0n || receiptBal > 0n) {
        results.push({ ...opt, optionBalance: optionBal, receiptBalance: receiptBal });
      }
    });
    return results;
  }, [data, options]);

  return { held, isLoading, refetch, hasWallet: Boolean(address) } as {
    held: OptionWithBalances[];
    isLoading: boolean;
    refetch: () => void;
    hasWallet: boolean;
  };
}

export default useMyOptionBalances;
