"use client";

import * as chains from "viem/chains";
import { useBrowseChain } from "../hooks/useBrowseChain";

/**
 * Wallet-independent chain picker. Drives `useBrowseChain` / `useBrowseChainId`
 * so users can browse options on any deployed chain before connecting a
 * wallet, and flip between chains without reconnecting.
 *
 * Mount once in the layout. The connected wallet's chain is independent of
 * this selection — when a user actually mints/exercises, we'll prompt them
 * to switch the wallet to the same chain (separate concern).
 */

const CHAIN_LABELS: Record<number, string> = Object.values(chains).reduce(
  (acc, c) => {
    if (c && typeof c === "object" && "id" in c && "name" in c) {
      acc[(c as { id: number }).id] = (c as { name: string }).name;
    }
    return acc;
  },
  {} as Record<number, string>,
);

export function ChainSelector({ className }: { className?: string }) {
  const { chainId, setChainId, supportedChainIds } = useBrowseChain();

  if (supportedChainIds.length <= 1) return null; // hide the picker if only one chain

  return (
    <select
      aria-label="Browse chain"
      className={
        className ??
        "rounded-md border border-base-300 bg-base-100 px-2 py-1 text-sm hover:bg-base-200 focus:outline-none focus:ring-2 focus:ring-primary"
      }
      value={chainId}
      onChange={e => setChainId(Number(e.target.value))}
    >
      {supportedChainIds.map(id => (
        <option key={id} value={id}>
          {CHAIN_LABELS[id] ?? `Chain ${id}`}
        </option>
      ))}
    </select>
  );
}
