import WebSocket from "ws";
import type {
  MarketMakerConnection,
  MarketMakerMessage,
  RFQMessage,
  QuoteResponse,
  DeclineResponse,
  RegisterMessage,
  OrderNotification,
} from "./types";

export class MarketMakerManager {
  private makers = new Map<string, MarketMakerConnection>();
  private wss: WebSocket.Server;
  private heartbeatInterval: NodeJS.Timeout;

  // Callbacks
  public onQuote?: (quote: QuoteResponse) => void;
  public onDecline?: (decline: DeclineResponse) => void;

  constructor(port: number) {
    this.wss = new WebSocket.Server({ port });
    console.log(`🔌 Market Maker WebSocket server listening on port ${port}`);

    this.wss.on("connection", (ws) => {
      console.log("📞 New market maker connection attempt");

      ws.on("message", (data) => {
        this.handleMessage(ws, data.toString());
      });

      ws.on("close", () => {
        this.handleDisconnect(ws);
      });

      ws.on("error", (error) => {
        console.error("WebSocket error:", error);
      });

      // Send initial heartbeat to prompt registration
      this.send(ws, { type: "heartbeat", timestamp: Date.now() });
    });

    // Start heartbeat to all connections
    this.heartbeatInterval = setInterval(() => {
      this.broadcast({ type: "heartbeat", timestamp: Date.now() });
    }, 30000);
  }

  private handleMessage(ws: WebSocket, data: string): void {
    try {
      const message = JSON.parse(data) as MarketMakerMessage;

      switch (message.type) {
        case "register":
          this.handleRegister(ws, message);
          break;
        case "quote":
          this.handleQuote(message);
          break;
        case "decline":
          this.handleDecline(message);
          break;
        case "heartbeat":
          // Acknowledge heartbeat
          break;
        default:
          console.log("Unknown message type:", data);
      }
    } catch (error) {
      console.error("Failed to parse message:", data, error);
    }
  }

  private handleRegister(ws: WebSocket, message: RegisterMessage): void {
    const connection: MarketMakerConnection = {
      id: message.maker_id,
      name: message.maker_name,
      ws,
      supportedTokens: message.supported_tokens.map((t) => t.toLowerCase()),
      isAlive: true,
    };

    this.makers.set(message.maker_id, connection);

    console.log(`✅ Registered market maker: ${message.maker_name} (${message.maker_id})`);
    console.log(`   Supported tokens: ${message.supported_tokens.length}`);

    // Send confirmation
    this.send(ws, {
      type: "registered",
      maker_id: message.maker_id,
      timestamp: Date.now(),
    });
  }

  private handleQuote(quote: QuoteResponse): void {
    console.log(`💰 Quote received from ${quote.maker_id} for RFQ ${quote.rfq_id}`);
    this.onQuote?.(quote);
  }

  private handleDecline(decline: DeclineResponse): void {
    console.log(`❌ Decline from ${decline.maker_id} for RFQ ${decline.rfq_id}: ${decline.reason}`);
    this.onDecline?.(decline);
  }

  private handleDisconnect(ws: WebSocket): void {
    for (const [id, maker] of this.makers.entries()) {
      if (maker.ws === ws) {
        console.log(`👋 Market maker disconnected: ${maker.name} (${id})`);
        this.makers.delete(id);
        break;
      }
    }
  }

  // Broadcast RFQ to relevant market makers
  public broadcastRFQ(rfq: RFQMessage): number {
    const buyToken = rfq.buy_tokens[0]?.token.toLowerCase();
    const sellToken = rfq.sell_tokens[0]?.token.toLowerCase();

    let sentCount = 0;

    for (const [id, maker] of this.makers.entries()) {
      // Check if maker supports either token
      const supportsBuy = buyToken && maker.supportedTokens.includes(buyToken);
      const supportsSell = sellToken && maker.supportedTokens.includes(sellToken);

      if (supportsBuy || supportsSell) {
        console.log(`📤 Sending RFQ ${rfq.rfq_id} to ${maker.name}`);
        this.send(maker.ws, rfq);
        sentCount++;
      }
    }

    console.log(`📡 Broadcast RFQ ${rfq.rfq_id} to ${sentCount} market makers`);
    return sentCount;
  }

  // Notify specific market maker about order
  public notifyOrder(makerId: string, notification: OrderNotification): void {
    const maker = this.makers.get(makerId);
    if (maker) {
      this.send(maker.ws, notification);
      console.log(`📬 Sent order notification to ${maker.name}`);
    }
  }

  private send(ws: WebSocket, message: any): void {
    if (ws.readyState === WebSocket.OPEN) {
      ws.send(JSON.stringify(message));
    }
  }

  private broadcast(message: any): void {
    const msgStr = JSON.stringify(message);
    for (const maker of this.makers.values()) {
      if (maker.ws.readyState === WebSocket.OPEN) {
        maker.ws.send(msgStr);
      }
    }
  }

  public getConnectedMakers(): MarketMakerConnection[] {
    return Array.from(this.makers.values());
  }

  public shutdown(): void {
    clearInterval(this.heartbeatInterval);
    this.wss.close();
  }
}
