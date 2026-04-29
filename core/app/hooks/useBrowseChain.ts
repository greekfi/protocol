"use client";

import { createContext, createElement, useCallback, useContext, useEffect, useMemo, useState, type ReactNode } from "react";
import { useChainId } from "wagmi";
import deployedContracts from "~~/abi/deployedContracts";

/**
 * "Browse chain" — the chain whose data the UI is currently showing. Distinct
 * from the connected wallet's chain because we want users to be able to
 * inspect options on any deployed chain *before* connecting a wallet (and
 * to flip between chains without reconnecting).
 *
 * Resolution order on first render:
 *   1. localStorage `greek.browseChain` (if a previously chosen chain)
 *   2. connected wallet's chain (if any, and it has a deployment)
 *   3. first chain with a Greek deployment (currently Arbitrum)
 *
 * After mount, the user can change the browse chain via {@link useBrowseChain}.
 * Wallet chain changes do NOT auto-override the user's pick — once they've
 * picked, it sticks until they change it.
 */

const LS_KEY = "greek.browseChain";

const SUPPORTED_CHAIN_IDS = (Object.keys(deployedContracts) as (keyof typeof deployedContracts | string)[])
  .map(k => Number(k))
  .filter(n => Number.isFinite(n) && n !== 31337); // hide foundry from the selector

export interface BrowseChainContextValue {
  chainId: number;
  setChainId: (id: number) => void;
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
  const walletChainId = useChainId();

  // Lazy initial — runs once. Picks localStorage → wallet → first supported.
  const [chainId, setChainIdState] = useState<number>(() => {
    const stored = readStoredChain();
    if (stored && SUPPORTED_CHAIN_IDS.includes(stored)) return stored;
    if (walletChainId && SUPPORTED_CHAIN_IDS.includes(walletChainId)) return walletChainId;
    return SUPPORTED_CHAIN_IDS[0] ?? 42161;
  });

  // If the user has never picked a chain explicitly and the wallet later
  // connects to a supported chain, drift the browse chain to follow it (one-time).
  useEffect(() => {
    if (readStoredChain() !== null) return; // user picked → don't override
    if (walletChainId && SUPPORTED_CHAIN_IDS.includes(walletChainId)) {
      setChainIdState(walletChainId);
    }
  }, [walletChainId]);

  const setChainId = useCallback((id: number) => {
    if (!SUPPORTED_CHAIN_IDS.includes(id)) {
      console.warn(`[useBrowseChain] unsupported chainId ${id}; ignoring`);
      return;
    }
    setChainIdState(id);
    writeStoredChain(id);
  }, []);

  const value = useMemo(
    () => ({ chainId, setChainId, supportedChainIds: SUPPORTED_CHAIN_IDS }),
    [chainId, setChainId],
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
