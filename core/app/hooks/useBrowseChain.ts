"use client";

import { createContext, createElement, useCallback, useContext, useMemo, useState, type ReactNode } from "react";
import { useAccount, useChainId, useSwitchChain } from "wagmi";
import deployedContracts from "~~/abi/deployedContracts";

/**
 * Single chain-selection abstraction:
 *
 * - When a wallet is connected, the browse chain *is* the wallet chain. The
 *   selector calls wagmi `switchChainAsync` so picking a chain re-points the
 *   wallet. (Fallback: if the user rejects the switch, the local pick still
 *   updates so they can browse without transacting.)
 * - When no wallet is connected, the browse chain is held in local state and
 *   persisted to localStorage. First-render default: previously picked chain
 *   → first chain with a Greek deployment (Arbitrum today).
 *
 * Net effect: there's only one chain UI to look at — the {@link ChainSelector}
 * in the header. RainbowKit's separate chain pill is hidden in the
 * WalletButton render to avoid the duplicated selector.
 */

const LS_KEY = "greek.browseChain";

const SUPPORTED_CHAIN_IDS = (Object.keys(deployedContracts) as (keyof typeof deployedContracts | string)[])
  .map(k => Number(k))
  .filter(n => Number.isFinite(n) && n !== 31337); // hide foundry from the selector

export interface BrowseChainContextValue {
  chainId: number;
  setChainId: (id: number) => void | Promise<void>;
  /** Chains the UI knows about, in render order. Excludes foundry (local dev). */
  supportedChainIds: number[];
}

const Ctx = createContext<BrowseChainContextValue | null>(null);

function readStoredChain(): number | null {
  if (typeof window === "undefined") return null;
  try {
    const raw = window.localStorage.getItem(LS_KEY);
    if (!raw) return null;
    const n = Number(raw);
    return Number.isFinite(n) ? n : null;
  } catch {
    return null;
  }
}

function writeStoredChain(id: number) {
  if (typeof window === "undefined") return;
  try {
    window.localStorage.setItem(LS_KEY, String(id));
  } catch {
    // Storage quota / private mode — fail silently, the in-memory state is enough.
  }
}

export function BrowseChainProvider({ children }: { children: ReactNode }) {
  const { isConnected } = useAccount();
  const walletChainId = useChainId();
  const { switchChainAsync } = useSwitchChain();

  // Local pick — used when no wallet is connected, and as the fallback if the
  // user rejects a wallet switch.
  const [localChainId, setLocalChainId] = useState<number>(() => {
    const stored = readStoredChain();
    if (stored && SUPPORTED_CHAIN_IDS.includes(stored)) return stored;
    if (walletChainId && SUPPORTED_CHAIN_IDS.includes(walletChainId)) return walletChainId;
    return SUPPORTED_CHAIN_IDS[0] ?? 42161;
  });

  // When connected, the browse chain mirrors the wallet chain. When not, it's
  // the local pick. Falls back to the first supported chain if the wallet is
  // on a chain we don't have a deployment for.
  const effectiveChainId = isConnected
    ? SUPPORTED_CHAIN_IDS.includes(walletChainId)
      ? walletChainId
      : SUPPORTED_CHAIN_IDS[0] ?? walletChainId
    : localChainId;

  const setChainId = useCallback(
    async (id: number) => {
      if (!SUPPORTED_CHAIN_IDS.includes(id)) {
        console.warn(`[useBrowseChain] unsupported chainId ${id}; ignoring`);
        return;
      }
      // Always update the local pick so an unconnected user (or a connected
      // user who later disconnects) sees their choice persisted.
      setLocalChainId(id);
      writeStoredChain(id);

      if (isConnected && walletChainId !== id) {
        try {
          await switchChainAsync({ chainId: id });
        } catch {
          // Wallet rejected the switch (or doesn't support it). The local
          // pick is already updated; the wallet stays where it was, and the
          // user can switch manually in their wallet UI.
        }
      }
    },
    [isConnected, walletChainId, switchChainAsync],
  );

  const value = useMemo(
    () => ({ chainId: effectiveChainId, setChainId, supportedChainIds: SUPPORTED_CHAIN_IDS }),
    [effectiveChainId, setChainId],
  );

  return createElement(Ctx.Provider, { value }, children);
}

export function useBrowseChain(): BrowseChainContextValue {
  const v = useContext(Ctx);
  if (!v) {
    throw new Error("useBrowseChain must be used inside <BrowseChainProvider> (mounted in app/providers.tsx).");
  }
  return v;
}

/** Convenience for the common case — consume just the chainId. */
export function useBrowseChainId(): number {
  return useBrowseChain().chainId;
}
