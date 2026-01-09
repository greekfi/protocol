// Bebop PMM WebSocket API types

export type Chain =
  | "ethereum"
  | "arbitrum"
  | "optimism"
  | "polygon"
  | "base"
  | "blast"
  | "bsc"
  | "mode"
  | "scroll"
  | "taiko"
  | "zksync";

export interface BebopConfig {
  chain: Chain;
  marketmaker: string;    // Request from Bebop team
  authorization: string;  // Request from Bebop team
  makerAddress: string;   // Your wallet address for signing quotes
}

// Incoming RFQ request from Bebop
export interface RFQRequest {
  type: "rfq";
  rfq_id: string;
  chain_id: number;
  taker_address: string;
  buy_tokens: TokenAmount[];
  sell_tokens: TokenAmount[];
  receiver_address?: string;
  expiry?: number;
}

export interface TokenAmount {
  token: string;  // token address
  amount: string; // amount in wei
}

// Quote response to send back
export interface QuoteResponse {
  type: "quote";
  rfq_id: string;
  maker_address: string;
  buy_tokens: TokenAmount[];
  sell_tokens: TokenAmount[];
  signature?: string;
  expiry: number;
}

// Decline response
export interface DeclineResponse {
  type: "decline";
  rfq_id: string;
  reason?: string;
}

// Order notification (after quote is accepted)
export interface OrderNotification {
  type: "order";
  rfq_id: string;
  order_hash: string;
  status: "pending" | "filled" | "cancelled" | "expired";
}

// Heartbeat
export interface Heartbeat {
  type: "heartbeat";
  timestamp: number;
}

export type IncomingMessage = RFQRequest | OrderNotification | Heartbeat;
export type OutgoingMessage = QuoteResponse | DeclineResponse;

// Event handler types
export type RFQHandler = (rfq: RFQRequest) => Promise<QuoteResponse | DeclineResponse | null>;
export type OrderHandler = (order: OrderNotification) => void;
