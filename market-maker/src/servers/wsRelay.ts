import WebSocket, { WebSocketServer } from "ws";
import { PricingRelay, PriceUpdateEvent, TAKER_CHAINS } from "../bebop/relay";
import { isOptionToken as isOptionTokenForChain } from "../config/options";

// Check if a pair contains one of our option tokens (for any chain)
function isPairForOptionToken(chainId: number, pair: string): boolean {
  const [base, quote] = pair.toLowerCase().split("/");
  return isOptionTokenForChain(chainId, base) || isOptionTokenForChain(chainId, quote);
}

// Client subscription state
interface ClientSubscription {
  chains: Set<number>; // Empty = all chains
  pairs: Set<string>; // Empty = all pairs (format: "base/quote")
}

// Message types from client
interface SubscribeMessage {
  type: "subscribe";
  chains?: number[]; // Chain IDs to subscribe to
  pairs?: string[]; // Pairs to subscribe to (format: "base/quote")
}

interface UnsubscribeMessage {
  type: "unsubscribe";
  chains?: number[];
  pairs?: string[];
}

interface PingMessage {
  type: "ping";
}

type ClientMessage = SubscribeMessage | UnsubscribeMessage | PingMessage;

// Message types to client
interface PriceMessage {
  type: "price";
  chainId: number;
  chain: string;
  pair: string;
  base: string;
  quote: string;
  lastUpdateTs: number;
  bids: [number, number][];
  asks: [number, number][];
}

interface StatusMessage {
  type: "status";
  connections: Record<string, boolean>;
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

export class PricingServer {
  private wss: WebSocketServer;
  private relay: PricingRelay;
  private clients: Map<WebSocket, ClientSubscription> = new Map();
  private heartbeatInterval: NodeJS.Timeout | null = null;

  constructor(relay: PricingRelay, port: number) {
    this.relay = relay;
    this.wss = new WebSocketServer({ port, host: "0.0.0.0" });

    this.setupServer();
    this.setupRelayListeners();
    this.startHeartbeat();

    console.log(`📡 Pricing WebSocket server listening on port ${port}`);
  }

  private setupServer(): void {
    this.wss.on("connection", (ws: WebSocket) => {
      console.log(`👤 Client connected (total: ${this.wss.clients.size})`);

      // Initialize with empty subscription (subscribes to nothing until explicitly subscribed)
      this.clients.set(ws, {
        chains: new Set(),
        pairs: new Set(),
      });

      // Send initial status
      this.sendStatus(ws);

      ws.on("message", (data: Buffer) => {
        this.handleClientMessage(ws, data);
      });

      ws.on("close", () => {
        console.log(`👤 Client disconnected (total: ${this.wss.clients.size - 1})`);
        this.clients.delete(ws);
      });

      ws.on("error", (error) => {
        console.error("Client WebSocket error:", error.message);
      });
    });
  }

  private setupRelayListeners(): void {
    // Forward price updates to subscribed clients
    this.relay.on("price", (event: PriceUpdateEvent) => {
      this.broadcastPrice(event);
    });

    // Notify clients of connection status changes
    this.relay.on("connected", ({ chain, chainId }) => {
      this.broadcastStatusUpdate();
    });

    this.relay.on("disconnected", ({ chain, chainId }) => {
      this.broadcastStatusUpdate();
    });
  }

  private handleClientMessage(ws: WebSocket, data: Buffer): void {
    try {
      const message: ClientMessage = JSON.parse(data.toString());
      console.log(`📨 Received message:`, message.type);

      switch (message.type) {
        case "subscribe":
          this.handleSubscribe(ws, message);
          break;
        case "unsubscribe":
          this.handleUnsubscribe(ws, message);
          break;
        case "ping":
          this.sendPong(ws);
          break;
        default:
          this.sendError(ws, `Unknown message type: ${(message as any).type}`);
      }
    } catch (error) {
      this.sendError(ws, `Invalid message format: ${(error as Error).message}`);
    }
  }

  private handleSubscribe(ws: WebSocket, message: SubscribeMessage): void {
    const subscription = this.clients.get(ws);
    if (!subscription) return;

    // Update chain subscriptions
    if (message.chains && message.chains.length > 0) {
      for (const chainId of message.chains) {
        subscription.chains.add(chainId);
      }
    } else if (message.chains && message.chains.length === 0) {
      // Empty array means subscribe to all chains
      subscription.chains.clear();
    }

    // Update pair subscriptions
    if (message.pairs && message.pairs.length > 0) {
      for (const pair of message.pairs) {
        subscription.pairs.add(pair.toLowerCase());
      }
    } else if (message.pairs && message.pairs.length === 0) {
      // Empty array means subscribe to all pairs
      subscription.pairs.clear();
    }

    console.log(
      `📝 Client subscribed: chains=${subscription.chains.size || "all"}, pairs=${subscription.pairs.size || "all"}`
    );

    // Send current cached prices for subscribed chains/pairs
    this.sendCachedPrices(ws, subscription);

    // Send updated status
    this.sendStatus(ws);
  }

  private handleUnsubscribe(ws: WebSocket, message: UnsubscribeMessage): void {
    const subscription = this.clients.get(ws);
    if (!subscription) return;

    if (message.chains) {
      for (const chainId of message.chains) {
        subscription.chains.delete(chainId);
      }
    }

    if (message.pairs) {
      for (const pair of message.pairs) {
        subscription.pairs.delete(pair.toLowerCase());
      }
    }

    this.sendStatus(ws);
  }

  private sendCachedPrices(ws: WebSocket, subscription: ClientSubscription): void {
    const allPrices = this.relay.getAllPrices();

    for (const [cacheKey, priceData] of allPrices) {
      // Parse cache key: "chainId:base/quote"
      const [chainIdStr, pair] = cacheKey.split(":");
      const chainId = parseInt(chainIdStr);

      // Filter: only send prices for our option tokens
      if (!isPairForOptionToken(chainId, pair)) {
        continue;
      }

      // Check if client is subscribed to this chain
      if (subscription.chains.size > 0 && !subscription.chains.has(chainId)) {
        continue;
      }

      // Check if client is subscribed to this pair
      if (subscription.pairs.size > 0 && !subscription.pairs.has(pair.toLowerCase())) {
        continue;
      }

      // Find chain name
      const chainEntry = Object.entries(TAKER_CHAINS).find(([_, config]) => config.chainId === chainId);
      const chainName = chainEntry ? chainEntry[0] : "unknown";

      const message: PriceMessage = {
        type: "price",
        chainId,
        chain: chainName,
        pair,
        base: priceData.base,
        quote: priceData.quote,
        lastUpdateTs: priceData.lastUpdateTs,
        bids: priceData.bids,
        asks: priceData.asks,
      };

      this.send(ws, message);
    }
  }

  private broadcastPrice(event: PriceUpdateEvent): void {
    // Filter: only broadcast prices for our option tokens
    if (!isPairForOptionToken(event.chainId, event.pair)) {
      return;
    }

    const message: PriceMessage = {
      type: "price",
      chainId: event.chainId,
      chain: event.chain,
      pair: event.pair,
      base: event.data.base,
      quote: event.data.quote,
      lastUpdateTs: event.data.lastUpdateTs,
      bids: event.data.bids,
      asks: event.data.asks,
    };

    for (const [ws, subscription] of this.clients) {
      // Check chain subscription
      if (subscription.chains.size > 0 && !subscription.chains.has(event.chainId)) {
        continue;
      }

      // Check pair subscription
      if (subscription.pairs.size > 0 && !subscription.pairs.has(event.pair.toLowerCase())) {
        continue;
      }

      this.send(ws, message);
    }
  }

  private broadcastStatusUpdate(): void {
    for (const [ws] of this.clients) {
      this.sendStatus(ws);
    }
  }

  private sendStatus(ws: WebSocket): void {
    const subscription = this.clients.get(ws);
    if (!subscription) return;

    const message: StatusMessage = {
      type: "status",
      connections: this.relay.getStatus(),
      subscribedChains: Array.from(subscription.chains),
      subscribedPairs: Array.from(subscription.pairs),
    };

    this.send(ws, message);
  }

  private sendPong(ws: WebSocket): void {
    const message: PongMessage = {
      type: "pong",
      timestamp: Date.now(),
    };
    this.send(ws, message);
  }

  private sendError(ws: WebSocket, errorMessage: string): void {
    const message: ErrorMessage = {
      type: "error",
      message: errorMessage,
    };
    this.send(ws, message);
  }

  private send(ws: WebSocket, message: object): void {
    if (ws.readyState === WebSocket.OPEN) {
      ws.send(JSON.stringify(message));
    }
  }

  // Heartbeat to detect stale connections
  private startHeartbeat(): void {
    this.heartbeatInterval = setInterval(() => {
      for (const ws of this.wss.clients) {
        if (ws.readyState === WebSocket.OPEN) {
          ws.ping();
        }
      }
    }, 30000); // Ping every 30 seconds
  }

  // Graceful shutdown
  stop(): void {
    console.log("🛑 Stopping Pricing Server");

    if (this.heartbeatInterval) {
      clearInterval(this.heartbeatInterval);
    }

    for (const ws of this.wss.clients) {
      ws.close(1000, "Server shutdown");
    }

    this.wss.close();
  }
}

// Factory function
export function startPricingServer(relay: PricingRelay, port: number = 3004): PricingServer {
  return new PricingServer(relay, port);
}

// Factory function for createWsRelay
export function createWsRelay(relay: PricingRelay): PricingServer {
  const port = parseInt(process.env.RELAY_WS_PORT || process.env.PORT || "3004");
  return new PricingServer(relay, port);
}
