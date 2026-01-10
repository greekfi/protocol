import WebSocket from "ws";
import type { RFQRequest, QuoteResponse } from "./types";
import { OPTIONS_LIST } from "./optionsList";

interface AggregatorConfig {
  wsUrl: string;
  makerId: string;
  makerName: string;
  makerAddress: string;
}

export class AggregatorClient {
  private ws: WebSocket | null = null;
  private config: AggregatorConfig;
  private reconnectAttempts = 0;
  private maxReconnectAttempts = 10;
  private isConnected = false;

  private rfqHandler: ((rfq: RFQRequest) => Promise<QuoteResponse | null>) | null = null;

  constructor(config: AggregatorConfig) {
    this.config = config;
  }

  onRFQ(handler: (rfq: RFQRequest) => Promise<QuoteResponse | null>): void {
    this.rfqHandler = handler;
  }

  async connect(): Promise<void> {
    return new Promise((resolve, reject) => {
      console.log(`Connecting to aggregator at ${this.config.wsUrl}...`);

      this.ws = new WebSocket(this.config.wsUrl);

      this.ws.on("open", () => {
        console.log("✅ Connected to aggregator");
        this.isConnected = true;
        this.reconnectAttempts = 0;

        // Register with aggregator
        this.register();

        resolve();
      });

      this.ws.on("message", (data) => {
        this.handleMessage(data.toString());
      });

      this.ws.on("close", (code, reason) => {
        console.log(`Disconnected from aggregator: ${code} - ${reason.toString()}`);
        this.isConnected = false;
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

  private register(): void {
    const supportedTokens = OPTIONS_LIST.map((opt) => opt.address);

    const registerMessage = {
      type: "register",
      maker_id: this.config.makerId,
      maker_name: this.config.makerName,
      maker_address: this.config.makerAddress,
      supported_tokens: supportedTokens,
    };

    console.log(`📝 Registering with aggregator...`);
    console.log(`   Maker: ${this.config.makerName}`);
    console.log(`   Supported tokens: ${supportedTokens.length}`);

    this.send(registerMessage);
  }

  private handleMessage(data: string): void {
    try {
      const message = JSON.parse(data);

      switch (message.type) {
        case "rfq":
          this.handleRFQ(message as RFQRequest);
          break;
        case "heartbeat":
          console.log("💓 Heartbeat from aggregator");
          break;
        case "registered":
          console.log("✅ Successfully registered with aggregator");
          break;
        case "order":
          console.log("📬 Order notification:", message);
          break;
        default:
          console.log("❓ Unknown message:", data);
      }
    } catch (error) {
      console.error("Failed to parse message:", data, error);
    }
  }

  private async handleRFQ(rfq: RFQRequest): Promise<void> {
    console.log(`\n📨 RFQ received: ${rfq.rfq_id}`);
    console.log(`   Buy: ${rfq.buy_tokens[0]?.amount} of ${rfq.buy_tokens[0]?.token}`);
    console.log(`   Sell: ${rfq.sell_tokens[0]?.amount} of ${rfq.sell_tokens[0]?.token}`);

    if (!this.rfqHandler) {
      console.warn("No RFQ handler registered, declining");
      this.decline(rfq.rfq_id, "No handler");
      return;
    }

    try {
      const response = await this.rfqHandler(rfq);

      if (response) {
        // Add maker_id to response
        const quoteWithId = {
          ...response,
          maker_id: this.config.makerId,
        };
        this.send(quoteWithId);
        console.log("✅ Sent quote to aggregator");
      } else {
        this.decline(rfq.rfq_id, "Unable to quote");
      }
    } catch (error) {
      console.error("RFQ handler error:", error);
      this.decline(rfq.rfq_id, "Handler error");
    }
  }

  private decline(rfqId: string, reason?: string): void {
    const response = {
      type: "decline",
      rfq_id: rfqId,
      maker_id: this.config.makerId,
      reason,
    };
    this.send(response);
  }

  private send(message: any): void {
    if (!this.ws || !this.isConnected) {
      console.error("Not connected, cannot send message");
      return;
    }

    const msgStr = JSON.stringify(message);
    console.log("📤 Sending to aggregator:", msgStr);
    this.ws.send(msgStr);
  }

  private scheduleReconnect(): void {
    if (this.reconnectAttempts >= this.maxReconnectAttempts) {
      console.error("Max reconnect attempts reached");
      return;
    }

    const delay = 1000 * Math.pow(2, this.reconnectAttempts);
    console.log(`Reconnecting in ${delay}ms...`);

    setTimeout(() => {
      this.reconnectAttempts++;
      this.connect().catch(console.error);
    }, delay);
  }

  disconnect(): void {
    if (this.ws) {
      this.ws.close(1000, "Client disconnect");
      this.ws = null;
    }
    this.isConnected = false;
  }
}
