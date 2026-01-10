import WebSocket from "ws";
import type {
  BebopConfig,
  IncomingMessage,
  OutgoingMessage,
  RFQRequest,
  OrderNotification,
  RFQHandler,
  OrderHandler,
  QuoteResponse,
  DeclineResponse,
} from "./types";

const BEBOP_WS_BASE = "wss://api.bebop.xyz/pmm";

export class BebopClient {
  private ws: WebSocket | null = null;
  private config: BebopConfig;
  private reconnectAttempts = 0;
  private maxReconnectAttempts = 10;
  private reconnectDelay = 1000;
  private heartbeatInterval: NodeJS.Timeout | null = null;
  private isConnected = false;

  private rfqHandler: RFQHandler | null = null;
  private orderHandler: OrderHandler | null = null;

  constructor(config: BebopConfig) {
    this.config = config;
  }

  get wsUrl(): string {
    return `${BEBOP_WS_BASE}/${this.config.chain}/v3/maker/quote`;
  }

  onRFQ(handler: RFQHandler): void {
    this.rfqHandler = handler;
  }

  onOrder(handler: OrderHandler): void {
    this.orderHandler = handler;
  }

  async connect(): Promise<void> {
    return new Promise((resolve, reject) => {
      console.log(`Connecting to ${this.wsUrl}...`);

      this.ws = new WebSocket(this.wsUrl, [], {
        headers: {
          marketmaker: this.config.marketmaker,
          authorization: this.config.authorization,
        },
      });

      this.ws.on("open", () => {
        console.log("Connected to Bebop");
        this.isConnected = true;
        this.reconnectAttempts = 0;
        this.startHeartbeat();
        resolve();
      });

      this.ws.on("message", (data) => {
        this.handleMessage(data.toString());
      });

      this.ws.on("close", (code, reason) => {
        console.log(`Disconnected: ${code} - ${reason.toString()}`);
        this.isConnected = false;
        this.stopHeartbeat();
        this.scheduleReconnect();
      });

      this.ws.on("error", (error) => {
        console.error("WebSocket error:", error.message);
        if (!this.isConnected) {
          reject(error);
        }
      });
    });
  }

  private startHeartbeat(): void {
    this.heartbeatInterval = setInterval(() => {
      if (this.isConnected) {
        this.ws?.ping();
      }
    }, 30000);
  }

  private stopHeartbeat(): void {
    if (this.heartbeatInterval) {
      clearInterval(this.heartbeatInterval);
      this.heartbeatInterval = null;
    }
  }

  private scheduleReconnect(): void {
    if (this.reconnectAttempts >= this.maxReconnectAttempts) {
      console.error("Max reconnect attempts reached");
      return;
    }

    const delay = this.reconnectDelay * Math.pow(2, this.reconnectAttempts);
    console.log(`Reconnecting in ${delay}ms...`);

    setTimeout(() => {
      this.reconnectAttempts++;
      this.connect().catch(console.error);
    }, delay);
  }

  private handleMessage(data: string): void {
    try {
      console.log("📨 Received message:", data);
      const message = JSON.parse(data) as IncomingMessage;

      switch (message.type) {
        case "rfq":
          this.handleRFQ(message as RFQRequest);
          break;
        case "order":
          this.handleOrder(message as OrderNotification);
          break;
        case "heartbeat":
          console.log("💓 Heartbeat received");
          break;
        default:
          console.log("❓ Unknown message type:", data);
      }
    } catch (error) {
      console.error("Failed to parse message:", data, error);
    }
  }

  private async handleRFQ(rfq: RFQRequest): Promise<void> {
    console.log(`RFQ received: ${rfq.rfq_id}`);

    if (!this.rfqHandler) {
      console.warn("No RFQ handler registered, declining");
      this.decline(rfq.rfq_id, "No handler");
      return;
    }

    try {
      const response = await this.rfqHandler(rfq);
      if (response) {
        this.send(response);
      }
    } catch (error) {
      console.error("RFQ handler error:", error);
      this.decline(rfq.rfq_id, "Handler error");
    }
  }

  private handleOrder(order: OrderNotification): void {
    console.log(`Order update: ${order.rfq_id} - ${order.status}`);
    this.orderHandler?.(order);
  }

  quote(rfqId: string, buyTokens: { token: string; amount: string }[], sellTokens: { token: string; amount: string }[], expiry: number): void {
    const response: QuoteResponse = {
      type: "quote",
      rfq_id: rfqId,
      maker_address: this.config.makerAddress,
      buy_tokens: buyTokens,
      sell_tokens: sellTokens,
      expiry,
    };
    this.send(response);
  }

  decline(rfqId: string, reason?: string): void {
    const response: DeclineResponse = {
      type: "decline",
      rfq_id: rfqId,
      reason,
    };
    this.send(response);
  }

  private send(message: OutgoingMessage): void {
    if (!this.ws || !this.isConnected) {
      console.error("Not connected, cannot send message");
      return;
    }

    const msgStr = JSON.stringify(message);
    console.log("📤 Sending message:", msgStr);
    this.ws.send(msgStr);
  }

  disconnect(): void {
    this.stopHeartbeat();
    if (this.ws) {
      this.ws.close(1000, "Client disconnect");
      this.ws = null;
    }
    this.isConnected = false;
  }
}
