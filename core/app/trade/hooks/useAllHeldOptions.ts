import { useMemo } from "react";
import { erc20Abi, type Address } from "viem";
import { useAccount, useReadContracts } from "wagmi";
import { useBrowseChainId } from "../../hooks/useBrowseChain";
import { useChainEvents } from "../../hooks/useChainEvents";

export interface HeldOption {
  option: Address;
  receipt: Address;
  collateral: Address;
  consideration: Address;
  expiration: bigint;
  strike: bigint;
  isPut: boolean;
  isEuro: boolean;
  /** Long-side balance (the Option ERC20). */
  optionBalance: bigint;
  /** Short-side balance (the Receipt ERC20). */
  receiptBalance: bigint;
}

/**
 * Returns every option in the factory's universe (sourced from event-sync)
 * where the connected wallet holds a non-zero long or short position.
 *
 * Reads `balanceOf(address)` on each option's long + short ERC20 in a single
 * `useReadContracts` batch.
 */
export function useAllHeldOptions() {
  const chainId = useBrowseChainId();
  const { address } = useAccount();
  const { data: events = [], isLoading: eventsLoading } = useChainEvents(chainId);

  const allOptions = useMemo(
    () =>
      events.map(e => ({
        option: e.args.option as Address,
        receipt: e.args.receipt as Address,
        collateral: e.args.collateral as Address,
        consideration: e.args.consideration as Address,
        expiration: BigInt(e.args.expirationDate),
        strike: BigInt(e.args.strike),
        isPut: e.args.isPut,
        isEuro: e.args.isEuro,
      })),
    [events],
  );

  const contracts = useMemo(() => {
    if (!address) return [];
    return allOptions.flatMap(opt => [
      { address: opt.option, abi: erc20Abi, functionName: "balanceOf" as const, args: [address] as const },
      { address: opt.receipt, abi: erc20Abi, functionName: "balanceOf" as const, args: [address] as const },
    ]);
  }, [address, allOptions]);

  const { data, isLoading: balancesLoading } = useReadContracts({
    contracts,
    query: { enabled: contracts.length > 0, refetchOnWindowFocus: false },
  });

  const held = useMemo<HeldOption[]>(() => {
    if (!data) return [];
    const results: HeldOption[] = [];
    allOptions.forEach((opt, i) => {
      const optionBalance = (data[i * 2]?.result as bigint | undefined) ?? 0n;
      const receiptBalance = (data[i * 2 + 1]?.result as bigint | undefined) ?? 0n;
      if (optionBalance > 0n || receiptBalance > 0n) {
        results.push({ ...opt, optionBalance, receiptBalance });
      }
    });
    return results;
  }, [data, allOptions]);

  return {
    held,
    isLoading: eventsLoading || balancesLoading,
    hasWallet: Boolean(address),
  };
}
