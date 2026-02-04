"use client";

import { ReactNode, createContext, useContext } from "react";
import { ConnectionStatus, PriceData, UsePricingStreamReturn, usePricingStream } from "../hooks/usePricingStream";

// Re-export types for convenience
export type { PriceData, ConnectionStatus, PriceLevel } from "../hooks/usePricingStream";

interface PricingContextValue extends UsePricingStreamReturn {}

const PricingContext = createContext<PricingContextValue | null>(null);

export interface PricingProviderProps {
  children: ReactNode;
  wsUrl?: string;
  chains?: number[];
  pairs?: string[];
  enabled?: boolean;
}

export function PricingProvider({ children, wsUrl, chains, pairs, enabled = true }: PricingProviderProps) {
  const pricing = usePricingStream({
    wsUrl,
    chains,
    pairs,
    enabled,
  });

  return <PricingContext.Provider value={pricing}>{children}</PricingContext.Provider>;
}

export function usePricing(): PricingContextValue {
  const context = useContext(PricingContext);

  if (!context) {
    throw new Error("usePricing must be used within a PricingProvider");
  }

  return context;
}

// Hook to get price for a specific pair
export function useTokenPrice(chainId: number, base: string, quote: string) {
  const { getPrice, getBestBid, getBestAsk, isConnected } = usePricing();
  void chainId; // Reserved for multi-chain support
  void quote; // Reserved for multi-quote support

  return {
    price: getPrice(base),
    bestBid: getBestBid(base),
    bestAsk: getBestAsk(base),
    isConnected,
  };
}
