// Market Maker WebSocket Messages
export interface MarketMakerConnection {
  id: string;
  name: string;
  ws: any; // WebSocket
  supportedTokens: string[]; // Token addresses they support
  isAlive: boolean;
}

// RFQ Request (from trader to aggregator)
export interface RFQRequest {
  rfq_id: string;
  buy_tokens: Array<{ token: string; amount: string }>;
  sell_tokens: Array<{ token: string; amount: string }>;
  taker_address: string;
  chain?: string;
}

// RFQ Message (aggregator to market maker)
export interface RFQMessage {
  type: "rfq";
  rfq_id: string;
  buy_tokens: Array<{ token: string; amount: string }>;
  sell_tokens: Array<{ token: string; amount: string }>;
  taker_address: string;
}

// Quote Response (market maker to aggregator)
export interface QuoteResponse {
  type: "quote";
  rfq_id: string;
  maker_id: string;
  maker_address: string;
  buy_tokens: Array<{ token: string; amount: string }>;
  sell_tokens: Array<{ token: string; amount: string }>;
  expiry: number;
  gas_estimate?: string;
}

// Decline Response (market maker to aggregator)
export interface DeclineResponse {
  type: "decline";
  rfq_id: string;
  maker_id: string;
  reason?: string;
}

// Registration Message (market maker to aggregator)
export interface RegisterMessage {
  type: "register";
  maker_id: string;
  maker_name: string;
  maker_address: string;
  supported_tokens: string[]; // Array of token addresses
  chains?: string[];
}

// Heartbeat
export interface HeartbeatMessage {
  type: "heartbeat";
  timestamp: number;
}

// Order Notification (aggregator to winning market maker)
export interface OrderNotification {
  type: "order";
  rfq_id: string;
  status: "pending" | "confirmed" | "failed";
  tx_hash?: string;
}

// Trader Quote Response (aggregator to trader)
export interface TraderQuoteResponse {
  buyAmount: string;
  sellAmount: string;
  price: string;
  estimatedGas: string;
  maker: string;
  tx: {
    to: string;
    data: string;
    value: string;
    gas: string;
  };
  approvalTarget?: string;
  expiry: number;
}

export type MarketMakerMessage =
  | RegisterMessage
  | QuoteResponse
  | DeclineResponse
  | HeartbeatMessage;

// Batch Pricing Request (trader to aggregator)
export interface BatchPricingRequest {
  pairs: Array<{
    tokenA: string;  // First token in the pair
    tokenB: string;  // Second token in the pair
  }>;
  taker_address?: string;
}

// Bidirectional Price for a single pair
export interface BidirectionalPrice {
  tokenA: string;
  tokenB: string;
  // A -> B direction (selling A to get B)
  sellA: {
    price: string | null;       // Price per 1 token A in terms of B
    maxInput: string | null;    // Max amount of A that can be sold
    maxOutput: string | null;   // Max amount of B that can be received
  };
  // B -> A direction (selling B to get A)
  sellB: {
    price: string | null;       // Price per 1 token B in terms of A
    maxInput: string | null;    // Max amount of B that can be sold
    maxOutput: string | null;   // Max amount of A that can be received
  };
}

// Batch Pricing Response
export interface BatchPricingResponse {
  pairs: BidirectionalPrice[];
  timestamp: number;
}
