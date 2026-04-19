import { WebSocketManager } from "./WebSocketManager";

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

export interface RfqPricingStreamCallbacks {
  onPrice: (price: RfqPriceData) => void;
  onConnectionChange: (connected: boolean) => void;
  onError: (error: string | null) => void;
}

/**
 * RfqPricingStreamManager - RFQ pricing stream WebSocket client
 *
 * Extends WebSocketManager with RFQ-specific message handling.
 */
export class RfqPricingStreamManager extends WebSocketManager<ServerMessage> {
  private options: string[];
  private underlyings: string[];

  constructor(
    wsUrl: string,
    private callbacks: RfqPricingStreamCallbacks,
    subscriptions?: { options?: string[]; underlyings?: string[] }
  ) {
    super(wsUrl, callbacks.onConnectionChange, callbacks.onError);
    this.options = subscriptions?.options || [];
    this.underlyings = subscriptions?.underlyings || [];
  }

  /**
   * Update subscription filters
   */
  updateSubscription(options?: string[], underlyings?: string[]) {
    if (options !== undefined) this.options = options;
    if (underlyings !== undefined) this.underlyings = underlyings;

    // If connected, update subscription
    if (this.isConnected()) {
      this.subscribe(this.options, this.underlyings);
    }
  }

  /**
   * Subscribe to specific options/underlyings
   */
  subscribe(options?: string[], underlyings?: string[]) {
    this.send({
      type: "subscribe",
      options,
      underlyings,
    });
  }

  /**
   * Unsubscribe from options/underlyings
   */
  unsubscribe(options?: string[], underlyings?: string[]) {
    this.send({
      type: "unsubscribe",
      options,
      underlyings,
    });
  }

  /**
   * Called when connection opens - subscribe to configured options
   */
  protected onOpen(): void {
    if (this.options.length > 0 || this.underlyings.length > 0) {
      this.subscribe(this.options, this.underlyings);
    } else {
      // Subscribe to all
      this.subscribe(undefined, undefined);
    }
  }

  /**
   * Handle incoming RFQ pricing messages
   */
  protected handleMessage(message: ServerMessage): void {
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
        this.callbacks.onPrice(priceData);
        break;
      }

      case "subscribed":
        console.log("📡 Subscribed to options:", message.options);
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
