import { WebSocketManager } from "./WebSocketManager";

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

export interface PricingStreamCallbacks {
  onPrice: (price: PriceData) => void;
  onConnectionChange: (connected: boolean) => void;
  onConnectionStatus: (status: ConnectionStatus) => void;
  onError: (error: string | null) => void;
}

/**
 * PricingStreamManager - Bebop pricing stream WebSocket client
 *
 * Extends WebSocketManager with pricing-specific message handling.
 */
export class PricingStreamManager extends WebSocketManager<ServerMessage> {
  private chains: number[];
  private pairs: string[];

  constructor(
    wsUrl: string,
    private callbacks: PricingStreamCallbacks,
    options?: { chains?: number[]; pairs?: string[] }
  ) {
    super(wsUrl, callbacks.onConnectionChange, callbacks.onError);
    this.chains = options?.chains || [];
    this.pairs = options?.pairs || [];
  }

  /**
   * Update subscription filters
   */
  updateSubscription(chains?: number[], pairs?: string[]) {
    if (chains !== undefined) this.chains = chains;
    if (pairs !== undefined) this.pairs = pairs;

    // If connected, update subscription
    if (this.isConnected()) {
      this.subscribe(this.chains, this.pairs);
    }
  }

  /**
   * Subscribe to specific chains/pairs
   */
  subscribe(chains?: number[], pairs?: string[]) {
    this.send({
      type: "subscribe",
      chains,
      pairs,
    });
  }

  /**
   * Unsubscribe from chains/pairs
   */
  unsubscribe(chains?: number[], pairs?: string[]) {
    this.send({
      type: "unsubscribe",
      chains,
      pairs,
    });
  }

  /**
   * Called when connection opens - subscribe to configured chains/pairs
   */
  protected onOpen(): void {
    if (this.chains.length > 0 || this.pairs.length > 0) {
      this.subscribe(this.chains, this.pairs);
    } else {
      // Subscribe to all by sending empty arrays
      this.subscribe([], []);
    }
  }

  /**
   * Handle incoming pricing messages
   */
  protected handleMessage(message: ServerMessage): void {
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
        this.callbacks.onPrice(priceData);
        break;
      }

      case "status":
        this.callbacks.onConnectionStatus(message.connections);
        break;

      case "pong":
        // Heartbeat response, connection is alive
        break;

      case "error":
        this.callbacks.onError(message.message);
        break;
    }
  }
}
