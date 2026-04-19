"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import { useQueryClient } from "@tanstack/react-query";
import {
  PricingStreamManager,
  type PriceData,
  type PriceLevel,
  type ConnectionStatus,
} from "../lib/PricingStreamManager";

export type { PriceLevel, PriceData, ConnectionStatus };

export interface UsePricingStreamOptions {
  wsUrl?: string;
  chains?: number[];
  pairs?: string[];
  enabled?: boolean;
  onPrice?: (price: PriceData) => void;
  onError?: (error: string) => void;
}

export interface UsePricingStreamReturn {
  prices: Map<string, PriceData>;
  getPrice: (tokenAddress: string) => PriceData | undefined;
  getBestBid: (tokenAddress: string) => number | undefined;
  getBestAsk: (tokenAddress: string) => number | undefined;
  isConnected: boolean;
  connectionStatus: ConnectionStatus;
  error: string | null;
  subscribe: (chains?: number[], pairs?: string[]) => void;
  unsubscribe: (chains?: number[], pairs?: string[]) => void;
}

const DEFAULT_WS_URL = process.env.NEXT_PUBLIC_PRICING_WS_URL || "ws://localhost:3004";

// USDC address (Ethereum mainnet)
const USDC = "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48";

// Extract non-USDC token from pair string "0xAAA.../0xBBB..."
const getTokenFromPair = (pair: string): string => {
  const [token1, token2] = pair.toLowerCase().split("/");
  // Return whichever is NOT USDC
  if (token2 === USDC.toLowerCase()) return token1;
  if (token1 === USDC.toLowerCase()) return token2;
  return token1; // fallback to first token
};

export function usePricingStream(options: UsePricingStreamOptions = {}): UsePricingStreamReturn {
  const { wsUrl = DEFAULT_WS_URL, chains = [], pairs = [], enabled = true, onPrice, onError } = options;

  const [prices, setPrices] = useState<Map<string, PriceData>>(new Map());
  const [isConnected, setIsConnected] = useState(false);
  const [connectionStatus, setConnectionStatus] = useState<ConnectionStatus>({});
  const [error, setError] = useState<string | null>(null);

  const queryClient = useQueryClient();
  const managerRef = useRef<PricingStreamManager | null>(null);

  // Store callbacks in refs to avoid recreating the manager
  const onPriceRef = useRef(onPrice);
  const onErrorRef = useRef(onError);
  const chainsRef = useRef(chains);
  const pairsRef = useRef(pairs);

  useEffect(() => {
    onPriceRef.current = onPrice;
  }, [onPrice]);

  useEffect(() => {
    onErrorRef.current = onError;
  }, [onError]);

  useEffect(() => {
    chainsRef.current = chains;
  }, [chains]);

  useEffect(() => {
    pairsRef.current = pairs;
  }, [pairs]);

  // Get price from cache - lookup by token address
  const getPrice = useCallback(
    (tokenAddress: string): PriceData | undefined => {
      const key = tokenAddress.toLowerCase();
      return prices.get(key);
    },
    [prices]
  );

  // Get best bid price
  const getBestBid = useCallback(
    (tokenAddress: string): number | undefined => {
      const price = getPrice(tokenAddress);
      return price?.bids[0]?.[0];
    },
    [getPrice]
  );

  // Get best ask price
  const getBestAsk = useCallback(
    (tokenAddress: string): number | undefined => {
      const price = getPrice(tokenAddress);
      return price?.asks[0]?.[0];
    },
    [getPrice]
  );

  // Subscribe to chains/pairs
  const subscribe = useCallback(
    (subscribeChains?: number[], subscribePairs?: string[]) => {
      managerRef.current?.subscribe(subscribeChains, subscribePairs);
    },
    []
  );

  // Unsubscribe from chains/pairs
  const unsubscribe = useCallback(
    (unsubscribeChains?: number[], unsubscribePairs?: string[]) => {
      managerRef.current?.unsubscribe(unsubscribeChains, unsubscribePairs);
    },
    []
  );

  // Create manager instance once per wsUrl only
  useEffect(() => {
    if (managerRef.current) return; // Prevent recreating if already exists

    managerRef.current = new PricingStreamManager(
      wsUrl,
      {
        onPrice: (priceData) => {
          const key = getTokenFromPair(priceData.pair);

          setPrices(prev => {
            const next = new Map(prev);
            next.set(key, priceData);
            return next;
          });

          // Update React Query cache for this pair
          queryClient.setQueryData(["price", priceData.chainId, priceData.base, priceData.quote], priceData);

          // Call external callback if provided
          onPriceRef.current?.(priceData);
        },
        onConnectionChange: setIsConnected,
        onConnectionStatus: setConnectionStatus,
        onError: (err) => {
          setError(err);
          if (err) onErrorRef.current?.(err);
        },
      },
      { chains: chainsRef.current, pairs: pairsRef.current }
    );

    return () => {
      managerRef.current?.destroy();
      managerRef.current = null;
    };
  }, [wsUrl, queryClient]); // Only recreate when wsUrl or queryClient changes

  // Handle enabled state changes
  useEffect(() => {
    if (enabled) {
      managerRef.current?.enable();
    } else {
      managerRef.current?.disable();
    }
  }, [enabled]);

  // Update subscription when chains/pairs change
  useEffect(() => {
    if (!managerRef.current) return;
    managerRef.current.updateSubscription(chains, pairs);
  }, [chains, pairs]);

  return {
    prices,
    getPrice,
    getBestBid,
    getBestAsk,
    isConnected,
    connectionStatus,
    error,
    subscribe,
    unsubscribe,
  };
}
