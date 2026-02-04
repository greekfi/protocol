/**
 * Bebop Pricing Stream
 *
 * Sends continuous pricing updates to Bebop via protobuf WebSocket
 */

import WebSocket from "ws";
import type { Pricer } from "../pricing/pricer";
import { bebop } from "./proto/pricing_pb";

const { LevelsSchema, LevelMsg, LevelInfo } = bebop;

export interface PricingStreamConfig {
  chain: string;
  chainId: number;
  marketmaker: string;
  authorization: string;
  makerAddress: string;
  usdcAddress: string;
}

export class PricingStream {
  private ws: WebSocket | null = null;
  private config: PricingStreamConfig;
  private pricer: Pricer;
  private interval: NodeJS.Timeout | null = null;
  private reconnectAttempts = 0;
  private maxReconnectAttempts = 10;

  constructor(config: PricingStreamConfig, pricer: Pricer) {
    this.config = config;
    this.pricer = pricer;
  }

  get wsUrl(): string {
    const BEBOP_WS_BASE = "wss://api.bebop.xyz/pmm";
    return `${BEBOP_WS_BASE}/${this.config.chain}/v3/maker/pricing?format=protobuf`;
  }

  connect(): void {
    console.log(`Connecting to pricing stream: ${this.wsUrl}`);

    this.ws = new WebSocket(this.wsUrl, [], {
      headers: {
        marketmaker: this.config.marketmaker,
        authorization: this.config.authorization,
      },
    });

    this.ws.on("open", () => {
      console.log("✅ Connected to Bebop Pricing Stream");
      this.reconnectAttempts = 0;
      this.startSending();
    });

    this.ws.on("message", (data) => {
      try {
        const text = data.toString();
        console.log("📨 Pricing response:", text);
        try {
          const json = JSON.parse(text);
          console.log("   ", JSON.stringify(json, null, 2));
        } catch {}
      } catch (error) {
        console.log("📨 Pricing response (binary):", Array.from(data as Buffer).slice(0, 100));
      }
    });

    this.ws.on("close", (code, reason) => {
      console.log(`❌ Pricing stream closed: ${code} - ${reason.toString()}`);
      this.stopSending();
      this.scheduleReconnect();
    });

    this.ws.on("error", (error) => {
      console.error("❌ Pricing stream error:", error.message);
    });
  }

  private startSending(): void {
    // Send pricing updates every 10 seconds
    this.interval = setInterval(() => {
      this.sendPricing();
    }, 10000);

    // Send initial update after 1 second
    setTimeout(() => this.sendPricing(), 1000);
  }

  private stopSending(): void {
    if (this.interval) {
      clearInterval(this.interval);
      this.interval = null;
    }
  }

  private sendPricing(): void {
    if (!this.ws || this.ws.readyState !== WebSocket.OPEN) {
      console.log("⚠️  Pricing stream not ready, skipping update");
      return;
    }

    try {
      // Build protobuf message
      const levelsSchema = new LevelsSchema();
      levelsSchema.chainId = this.config.chainId;
      levelsSchema.msgTopic = "pricing";
      levelsSchema.msgType = "update";
      levelsSchema.msg = new LevelMsg();
      levelsSchema.msg.makerAddress = this.hexToBytes(this.config.makerAddress);
      levelsSchema.msg.levels = [];

      // Get all option addresses from pricer
      const optionAddresses = this.pricer.getOptionAddresses();
      console.log(`📊 Building pricing update for ${optionAddresses.length} options...`);

      // Add levels for each option
      for (const addr of optionAddresses) {
        const pricing = this.pricer.getPrice(addr);
        if (!pricing || pricing.bids.length === 0 || pricing.asks.length === 0) {
          continue;
        }

        const levelInfo = new LevelInfo();
        levelInfo.baseAddress = this.hexToBytes(addr);
        levelInfo.baseDecimals = 6; // Option tokens have 6 decimals
        levelInfo.quoteAddress = this.hexToBytes(this.config.usdcAddress);
        levelInfo.quoteDecimals = 6; // USDC has 6 decimals

        const [bidPrice] = pricing.bids[0];
        const [askPrice] = pricing.asks[0];

        console.log(`   ${addr.slice(0, 10)}... bid=$${bidPrice.toFixed(2)} ask=$${askPrice.toFixed(2)}`);

        // Flatten bids/asks: [price, amount, price, amount, ...]
        levelInfo.bids = [bidPrice, 1000.0];
        levelInfo.asks = [askPrice, 1000.0];

        levelsSchema.msg.levels.push(levelInfo);
      }

      // Encode to protobuf bytes
      const buffer = LevelsSchema.encode(levelsSchema).finish();

      console.log(`📤 Sending protobuf pricing update (${buffer.length} bytes, ${levelsSchema.msg.levels.length} options)`);

      this.ws.send(buffer);
    } catch (error) {
      console.error("❌ Failed to send pricing update:", error);
    }
  }

  private hexToBytes(hex: string): Buffer {
    const cleanHex = hex.startsWith("0x") ? hex.slice(2) : hex;
    return Buffer.from(cleanHex, "hex");
  }

  private scheduleReconnect(): void {
    if (this.reconnectAttempts >= this.maxReconnectAttempts) {
      console.error("Max reconnect attempts reached for pricing stream");
      return;
    }

    const delay = 5000 * Math.pow(2, this.reconnectAttempts);
    console.log(`Reconnecting pricing stream in ${delay}ms...`);

    setTimeout(() => {
      this.reconnectAttempts++;
      this.connect();
    }, delay);
  }

  disconnect(): void {
    this.stopSending();
    if (this.ws) {
      this.ws.close(1000, "Client disconnect");
      this.ws = null;
    }
  }
}
