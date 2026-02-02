"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import { useQueryClient } from "@tanstack/react-query";

// RFQ-Direct price update format
export interface RfqPriceData {
  optionAddress: string;
  bid: number;
  ask: number;
  mid: number;
  spotPrice: number;
  iv: number;
  delta: number;
  timestamp: number;
}

// WebSocket message types from rfq-direct
interface PriceMessage {
  type: "price";
  optionAddress: string;
  bid: string;
  ask: string;
  mid: string;
  spotPrice: number;
  iv: number;
  delta: number;
  timestamp: number;
}

interface SubscribedMessage {
  type: "subscribed";
  options: string[];
}

interface PongMessage {
  type: "pong";
  timestamp: number;
}

interface ErrorMessage {
  type: "error";
  message: string;
}

type ServerMessage = PriceMessage | SubscribedMessage | PongMessage | ErrorMessage;

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

  const wsRef = useRef<WebSocket | null>(null);
  const reconnectTimeoutRef = useRef<NodeJS.Timeout | null>(null);
  const reconnectAttempts = useRef(0);
  const maxReconnectAttempts = 10;
  const queryClient = useQueryClient();

  // Store options/underlyings in refs to avoid connection churn
  const optionsRef = useRef(optionAddresses);
  const underlyingsRef = useRef(underlyings);
  optionsRef.current = optionAddresses;
  underlyingsRef.current = underlyings;

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

  // Send message to server
  const sendMessage = useCallback((message: object) => {
    if (wsRef.current?.readyState === WebSocket.OPEN) {
      wsRef.current.send(JSON.stringify(message));
    }
  }, []);

  // Subscribe to options/underlyings
  const subscribe = useCallback(
    (subscribeOptions?: string[], subscribeUnderlyings?: string[]) => {
      sendMessage({
        type: "subscribe",
        options: subscribeOptions,
        underlyings: subscribeUnderlyings,
      });
    },
    [sendMessage]
  );

  // Unsubscribe from options/underlyings
  const unsubscribe = useCallback(
    (unsubscribeOptions?: string[], unsubscribeUnderlyings?: string[]) => {
      sendMessage({
        type: "unsubscribe",
        options: unsubscribeOptions,
        underlyings: unsubscribeUnderlyings,
      });
    },
    [sendMessage]
  );

  // Handle incoming message
  const handleMessage = useCallback(
    (event: MessageEvent) => {
      try {
        const message: ServerMessage = JSON.parse(event.data);

        switch (message.type) {
          case "price": {
            const priceData: RfqPriceData = {
              optionAddress: message.optionAddress,
              bid: parseFloat(message.bid),
              ask: parseFloat(message.ask),
              mid: parseFloat(message.mid),
              spotPrice: message.spotPrice,
              iv: message.iv,
              delta: message.delta,
              timestamp: message.timestamp,
            };

            const key = message.optionAddress.toLowerCase();

            setPrices((prev) => {
              const next = new Map(prev);
              next.set(key, priceData);
              return next;
            });

            // Update React Query cache
            queryClient.setQueryData(["rfqPrice", message.optionAddress], priceData);

            onPrice?.(priceData);
            break;
          }

          case "subscribed":
            console.log("📡 Subscribed to options:", message.options);
            break;

          case "pong":
            // Heartbeat response
            break;

          case "error":
            setError(message.message);
            onError?.(message.message);
            break;
        }
      } catch (err) {
        console.error("Failed to parse RFQ pricing message:", err);
      }
    },
    [queryClient, onPrice, onError]
  );

  // Connect to WebSocket
  const connect = useCallback(() => {
    if (!enabled || !wsUrl) return;

    // Clean up existing connection
    if (wsRef.current) {
      wsRef.current.close();
    }

    try {
      const ws = new WebSocket(wsUrl);
      wsRef.current = ws;

      ws.onopen = () => {
        console.log("📡 Connected to RFQ pricing stream");
        setIsConnected(true);
        setError(null);
        reconnectAttempts.current = 0;

        // Subscribe to configured options/underlyings
        const currentOptions = optionsRef.current;
        const currentUnderlyings = underlyingsRef.current;
        if (currentOptions.length > 0 || currentUnderlyings.length > 0) {
          subscribe(currentOptions, currentUnderlyings);
        } else {
          // Subscribe to all
          subscribe(undefined, undefined);
        }
      };

      ws.onmessage = handleMessage;

      ws.onclose = (event) => {
        console.log(`📡 Disconnected from RFQ pricing stream: ${event.code}`);
        setIsConnected(false);
        wsRef.current = null;

        // Attempt reconnection with exponential backoff
        if (enabled && reconnectAttempts.current < maxReconnectAttempts) {
          const delay = Math.min(1000 * Math.pow(2, reconnectAttempts.current), 30000);
          console.log(`📡 Reconnecting in ${delay}ms (attempt ${reconnectAttempts.current + 1})`);

          reconnectTimeoutRef.current = setTimeout(() => {
            reconnectAttempts.current++;
            connect();
          }, delay);
        }
      };

      ws.onerror = (event) => {
        console.error("📡 RFQ pricing stream error:", event);
        setError("WebSocket connection error");
      };
    } catch (err) {
      console.error("Failed to connect to RFQ pricing stream:", err);
      setError(`Failed to connect: ${(err as Error).message}`);
    }
  }, [enabled, wsUrl, subscribe, handleMessage]);

  // Start ping interval
  useEffect(() => {
    if (!isConnected) return;

    const pingInterval = setInterval(() => {
      sendMessage({ type: "ping" });
    }, 30000);

    return () => clearInterval(pingInterval);
  }, [isConnected, sendMessage]);

  // Connect on mount
  useEffect(() => {
    if (enabled) {
      connect();
    }

    return () => {
      if (reconnectTimeoutRef.current) {
        clearTimeout(reconnectTimeoutRef.current);
      }
      if (wsRef.current) {
        wsRef.current.close();
        wsRef.current = null;
      }
    };
  }, [enabled, connect]);

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
