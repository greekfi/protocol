"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import { useQueryClient } from "@tanstack/react-query";
import { RfqPricingStreamManager, type RfqPriceData } from "../../lib/RfqPricingStreamManager";

export type { RfqPriceData };

export interface UseRfqPricingStreamOptions {
  wsUrl?: string;
  options?: string[];
  underlyings?: string[];
  enabled?: boolean;
  onPrice?: (price: RfqPriceData) => void;
  onError?: (error: string) => void;
}

export interface UseRfqPricingStreamReturn {
  prices: Map<string, RfqPriceData>;
  getPrice: (optionAddress: string) => RfqPriceData | undefined;
  getBestBid: (optionAddress: string) => number | undefined;
  getBestAsk: (optionAddress: string) => number | undefined;
  isConnected: boolean;
  error: string | null;
  subscribe: (options?: string[], underlyings?: string[]) => void;
  unsubscribe: (options?: string[], underlyings?: string[]) => void;
}

const DEFAULT_WS_URL = process.env.NEXT_PUBLIC_RFQ_WS_URL || "ws://localhost:3011";

export function useRfqPricingStream(options: UseRfqPricingStreamOptions = {}): UseRfqPricingStreamReturn {
  const {
    wsUrl = DEFAULT_WS_URL,
    options: optionAddresses = [],
    underlyings = [],
    enabled = true,
    onPrice,
    onError,
  } = options;

  const [prices, setPrices] = useState<Map<string, RfqPriceData>>(new Map());
  const [isConnected, setIsConnected] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const queryClient = useQueryClient();
  const managerRef = useRef<RfqPricingStreamManager | null>(null);

  // Get price from cache
  const getPrice = useCallback(
    (optionAddress: string): RfqPriceData | undefined => {
      return prices.get(optionAddress.toLowerCase());
    },
    [prices]
  );

  // Get best bid price
  const getBestBid = useCallback(
    (optionAddress: string): number | undefined => {
      const price = getPrice(optionAddress);
      return price?.bid;
    },
    [getPrice]
  );

  // Get best ask price
  const getBestAsk = useCallback(
    (optionAddress: string): number | undefined => {
      const price = getPrice(optionAddress);
      return price?.ask;
    },
    [getPrice]
  );

  // Subscribe to options/underlyings
  const subscribe = useCallback(
    (subscribeOptions?: string[], subscribeUnderlyings?: string[]) => {
      managerRef.current?.subscribe(subscribeOptions, subscribeUnderlyings);
    },
    []
  );

  // Unsubscribe from options/underlyings
  const unsubscribe = useCallback(
    (unsubscribeOptions?: string[], unsubscribeUnderlyings?: string[]) => {
      managerRef.current?.unsubscribe(unsubscribeOptions, unsubscribeUnderlyings);
    },
    []
  );

  // Create manager instance once per wsUrl
  useEffect(() => {
    managerRef.current = new RfqPricingStreamManager(
      wsUrl,
      {
        onPrice: (priceData) => {
          const key = priceData.optionAddress.toLowerCase();

          setPrices(prev => {
            const next = new Map(prev);
            next.set(key, priceData);
            return next;
          });

          // Update React Query cache
          queryClient.setQueryData(["rfqPrice", priceData.optionAddress], priceData);

          // Call external callback if provided
          onPrice?.(priceData);
        },
        onConnectionChange: setIsConnected,
        onError: (err) => {
          setError(err);
          if (err) onError?.(err);
        },
      },
      { options: optionAddresses, underlyings }
    );

    return () => {
      managerRef.current?.destroy();
      managerRef.current = null;
    };
  }, [wsUrl, queryClient, onPrice, onError, optionAddresses, underlyings]);

  // Handle enabled state changes
  useEffect(() => {
    if (enabled) {
      managerRef.current?.enable();
    } else {
      managerRef.current?.disable();
    }
  }, [enabled]);

  // Update subscription when options/underlyings change
  useEffect(() => {
    managerRef.current?.updateSubscription(optionAddresses, underlyings);
  }, [optionAddresses, underlyings]);

  return {
    prices,
    getPrice,
    getBestBid,
    getBestAsk,
    isConnected,
    error,
    subscribe,
    unsubscribe,
  };
}
