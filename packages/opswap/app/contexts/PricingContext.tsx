"use client";

import { createContext, useContext, ReactNode } from "react";
import {
  usePricingStream,
  UsePricingStreamReturn,
  PriceData,
  ConnectionStatus,
} from "../hooks/usePricingStream";

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

export function PricingProvider({
  children,
  wsUrl,
  chains,
  pairs,
  enabled = true,
}: PricingProviderProps) {
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

  return {
    price: getPrice(chainId, base, quote),
    bestBid: getBestBid(chainId, base, quote),
    bestAsk: getBestAsk(chainId, base, quote),
    isConnected,
  };
}
