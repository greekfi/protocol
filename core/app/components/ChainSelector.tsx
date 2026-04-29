"use client";

import { useEffect, useRef, useState } from "react";
import * as chains from "viem/chains";
import { useAccount } from "wagmi";
import { useBrowseChain } from "../hooks/useBrowseChain";
import { SERIF_STACK } from "./SiteHeader";

/**
 * Fallback chain picker for the *unconnected* case. When a wallet is
 * connected, RainbowKit's native chain pill + modal (rendered inside
 * WalletButton) handles chain selection — it has chain icons and the
 * polished switch-chain UI. RainbowKit's modal can't open without a wallet,
 * so this component fills that gap with a minimal popover dropdown.
 *
 * Renders nothing when a wallet is connected.
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

const BUTTON_CLASS =
  "px-3.5 py-2 rounded-lg border border-gray-700 hover:border-blue-300 transition-colors text-base sm:text-lg text-gray-300 flex items-center gap-2";

export function ChainSelector({ className }: { className?: string }) {
  const { isConnected } = useAccount();
  const { chainId, setChainId, supportedChainIds } = useBrowseChain();
  const [open, setOpen] = useState(false);
  const wrapperRef = useRef<HTMLDivElement | null>(null);

  // Close on click-outside.
  useEffect(() => {
    if (!open) return;
    function onDocClick(e: MouseEvent) {
      if (!wrapperRef.current) return;
      if (!wrapperRef.current.contains(e.target as Node)) setOpen(false);
    }
    function onEsc(e: KeyboardEvent) {
      if (e.key === "Escape") setOpen(false);
    }
    document.addEventListener("mousedown", onDocClick);
    document.addEventListener("keydown", onEsc);
    return () => {
      document.removeEventListener("mousedown", onDocClick);
      document.removeEventListener("keydown", onEsc);
    };
  }, [open]);

  // Connected → RainbowKit's chain pill in WalletButton handles it.
  if (isConnected) return null;
  if (supportedChainIds.length <= 1) return null;

  const currentLabel = CHAIN_LABELS[chainId] ?? `Chain ${chainId}`;

  return (
    <div ref={wrapperRef} className={`relative ${className ?? ""}`} style={{ fontFamily: SERIF_STACK, fontWeight: 400 }}>
      <button
        type="button"
        onClick={() => setOpen(o => !o)}
        aria-haspopup="listbox"
        aria-expanded={open}
        className={BUTTON_CLASS}
      >
        <span>{currentLabel}</span>
        <svg
          className={`w-3 h-3 text-gray-400 transition-transform ${open ? "rotate-180" : ""}`}
          viewBox="0 0 12 12"
          fill="none"
          aria-hidden="true"
        >
          <path d="M2 4 L6 8 L10 4" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" />
        </svg>
      </button>

      {open && (
        <div
          role="listbox"
          aria-label="Browse chain"
          className="absolute right-0 mt-2 min-w-[10rem] rounded-lg border border-gray-700 bg-black/95 backdrop-blur-sm shadow-xl overflow-hidden z-50"
        >
          {supportedChainIds.map(id => {
            const selected = id === chainId;
            return (
              <button
                key={id}
                type="button"
                role="option"
                aria-selected={selected}
                onClick={() => {
                  setChainId(id);
                  setOpen(false);
                }}
                className={`w-full text-left px-3.5 py-2 text-base sm:text-lg flex items-center justify-between gap-3 transition-colors ${
                  selected ? "text-blue-300 bg-blue-500/5" : "text-gray-300 hover:bg-gray-800/60 hover:text-blue-300"
                }`}
              >
                <span>{CHAIN_LABELS[id] ?? `Chain ${id}`}</span>
                {selected && (
                  <svg className="w-4 h-4 text-blue-300" viewBox="0 0 16 16" fill="none" aria-hidden="true">
                    <path
                      d="M3 8 L6.5 11.5 L13 5"
                      stroke="currentColor"
                      strokeWidth="1.75"
                      strokeLinecap="round"
                      strokeLinejoin="round"
                    />
                  </svg>
                )}
              </button>
            );
          })}
        </div>
      )}
    </div>
  );
}
