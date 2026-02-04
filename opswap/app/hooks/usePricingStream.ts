"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import { useQueryClient } from "@tanstack/react-query";

// Price level: [price, quantity]
export type PriceLevel = [number, number];

// Price data for a trading pair
export interface PriceData {
  chainId: number;
  chain: string;
  pair: string;
  base: string;
  quote: string;
  lastUpdateTs: number;
  bids: PriceLevel[];
  asks: PriceLevel[];
}

// Connection status
export interface ConnectionStatus {
  [chain: string]: boolean;
}

// WebSocket message types
interface PriceMessage {
  type: "price";
  chainId: number;
  chain: string;
  pair: string;
  base: string;
  quote: string;
  lastUpdateTs: number;
  bids: PriceLevel[];
  asks: PriceLevel[];
}

interface StatusMessage {
  type: "status";
  connections: ConnectionStatus;
  subscribedChains: number[];
  subscribedPairs: string[];
}

interface PongMessage {
  type: "pong";
  timestamp: number;
}

interface ErrorMessage {
  type: "error";
  message: string;
}

type ServerMessage = PriceMessage | StatusMessage | PongMessage | ErrorMessage;

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

export function usePricingStream(options: UsePricingStreamOptions = {}): UsePricingStreamReturn {
  const {
    wsUrl = DEFAULT_WS_URL,
    chains = [],
    pairs = [],
    enabled = true,
    onPrice,
    onError,
  } = options;

  const [prices, setPrices] = useState<Map<string, PriceData>>(new Map());
  const [isConnected, setIsConnected] = useState(false);
  const [connectionStatus, setConnectionStatus] = useState<ConnectionStatus>({});
  const [error, setError] = useState<string | null>(null);

  const wsRef = useRef<WebSocket | null>(null);
  const reconnectTimeoutRef = useRef<NodeJS.Timeout | null>(null);
  const reconnectAttempts = useRef(0);
  const maxReconnectAttempts = 10;
  const queryClient = useQueryClient();

  // Store chains/pairs in refs to avoid connection churn
  const chainsRef = useRef(chains);
  const pairsRef = useRef(pairs);
  chainsRef.current = chains;
  pairsRef.current = pairs;

  // USDC address (Ethereum mainnet)
  const USDC = "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48";

  // Extract non-USDC token from pair string "0xAAA.../0xBBB..."
  const getTokenFromPair = useCallback((pair: string): string => {
    const [token1, token2] = pair.toLowerCase().split("/");
    // Return whichever is NOT USDC
    if (token2 === USDC.toLowerCase()) return token1;
    if (token1 === USDC.toLowerCase()) return token2;
    return token1; // fallback to first token
  }, []);

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

  // Send message to server
  const sendMessage = useCallback((message: object) => {
    if (wsRef.current?.readyState === WebSocket.OPEN) {
      wsRef.current.send(JSON.stringify(message));
    }
  }, []);

  // Subscribe to chains/pairs
  const subscribe = useCallback(
    (subscribeChains?: number[], subscribePairs?: string[]) => {
      sendMessage({
        type: "subscribe",
        chains: subscribeChains,
        pairs: subscribePairs,
      });
    },
    [sendMessage]
  );

  // Unsubscribe from chains/pairs
  const unsubscribe = useCallback(
    (unsubscribeChains?: number[], unsubscribePairs?: string[]) => {
      sendMessage({
        type: "unsubscribe",
        chains: unsubscribeChains,
        pairs: unsubscribePairs,
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
            const priceData: PriceData = {
              chainId: message.chainId,
              chain: message.chain,
              pair: message.pair,
              base: message.base,
              quote: message.quote,
              lastUpdateTs: message.lastUpdateTs,
              bids: message.bids,
              asks: message.asks,
            };

            const key = getTokenFromPair(message.pair);

            setPrices((prev) => {
              const next = new Map(prev);
              next.set(key, priceData);
              return next;
            });

            // Update React Query cache for this pair
            queryClient.setQueryData(["price", message.chainId, message.base, message.quote], priceData);

            onPrice?.(priceData);
            break;
          }

          case "status":
            setConnectionStatus(message.connections);
            break;

          case "pong":
            // Heartbeat response, connection is alive
            break;

          case "error":
            setError(message.message);
            onError?.(message.message);
            break;
        }
      } catch (err) {
        console.error("Failed to parse pricing message:", err);
      }
    },
    [getTokenFromPair, queryClient, onPrice, onError]
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
        console.log("📡 Connected to pricing stream");
        setIsConnected(true);
        setError(null);
        reconnectAttempts.current = 0;

        // Subscribe to configured chains/pairs (use refs for stable reference)
        const currentChains = chainsRef.current;
        const currentPairs = pairsRef.current;
        if (currentChains.length > 0 || currentPairs.length > 0) {
          subscribe(currentChains, currentPairs);
        } else {
          // Subscribe to all by sending empty arrays
          subscribe([], []);
        }
      };

      ws.onmessage = handleMessage;

      ws.onclose = (event) => {
        console.log(`📡 Disconnected from pricing stream: ${event.code}`);
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
        console.error("📡 Pricing stream error:", event);
        setError("WebSocket connection error");
      };
    } catch (err) {
      console.error("Failed to connect to pricing stream:", err);
      setError(`Failed to connect: ${(err as Error).message}`);
    }
  }, [enabled, wsUrl, subscribe, handleMessage]);

  // Start ping interval to keep connection alive
  useEffect(() => {
    if (!isConnected) return;

    const pingInterval = setInterval(() => {
      sendMessage({ type: "ping" });
    }, 30000);

    return () => clearInterval(pingInterval);
  }, [isConnected, sendMessage]);

  // Connect on mount, disconnect on unmount
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
    connectionStatus,
    error,
    subscribe,
    unsubscribe,
  };
}
