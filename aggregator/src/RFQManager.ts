import { v4 as uuidv4 } from "uuid";
import type {
  RFQRequest,
  RFQMessage,
  QuoteResponse,
  DeclineResponse,
  TraderQuoteResponse,
} from "./types";

interface PendingRFQ {
  rfqId: string;
  request: RFQRequest;
  quotes: QuoteResponse[];
  declines: DeclineResponse[];
  createdAt: number;
  timeout: NodeJS.Timeout;
  resolve: (quote: TraderQuoteResponse | null) => void;
}

export class RFQManager {
  private pendingRFQs = new Map<string, PendingRFQ>();
  private readonly RFQ_TIMEOUT = 5000; // 5 seconds to collect quotes

  // Create new RFQ and return promise that resolves with best quote
  public createRFQ(request: Omit<RFQRequest, "rfq_id">): Promise<TraderQuoteResponse | null> {
    const rfqId = uuidv4();
    const rfqRequest: RFQRequest = {
      ...request,
      rfq_id: rfqId,
    };

    console.log(`\n🔔 New RFQ created: ${rfqId}`);
    console.log(`   Buy: ${request.buy_tokens[0]?.amount} of ${request.buy_tokens[0]?.token}`);
    console.log(`   Sell: ${request.sell_tokens[0]?.amount} of ${request.sell_tokens[0]?.token}`);

    return new Promise((resolve) => {
      const timeout = setTimeout(() => {
        this.resolveRFQ(rfqId);
      }, this.RFQ_TIMEOUT);

      const pending: PendingRFQ = {
        rfqId,
        request: rfqRequest,
        quotes: [],
        declines: [],
        createdAt: Date.now(),
        timeout,
        resolve,
      };

      this.pendingRFQs.set(rfqId, pending);
    });
  }

  // Get RFQ message to broadcast to market makers
  public getRFQMessage(rfqId: string): RFQMessage | null {
    const pending = this.pendingRFQs.get(rfqId);
    if (!pending) return null;

    return {
      type: "rfq",
      rfq_id: pending.request.rfq_id,
      buy_tokens: pending.request.buy_tokens,
      sell_tokens: pending.request.sell_tokens,
      taker_address: pending.request.taker_address,
    };
  }

  // Add quote from market maker
  public addQuote(quote: QuoteResponse): void {
    const pending = this.pendingRFQs.get(quote.rfq_id);
    if (!pending) {
      console.log(`⚠️  Quote for unknown RFQ: ${quote.rfq_id}`);
      return;
    }

    pending.quotes.push(quote);
    console.log(`💰 Quote ${pending.quotes.length} received for RFQ ${quote.rfq_id}`);
    console.log(`   Maker: ${quote.maker_id}`);
    console.log(`   Buy: ${quote.buy_tokens[0]?.amount}`);
    console.log(`   Sell: ${quote.sell_tokens[0]?.amount}`);
  }

  // Add decline from market maker
  public addDecline(decline: DeclineResponse): void {
    const pending = this.pendingRFQs.get(decline.rfq_id);
    if (!pending) {
      console.log(`⚠️  Decline for unknown RFQ: ${decline.rfq_id}`);
      return;
    }

    pending.declines.push(decline);
    console.log(`❌ Decline received for RFQ ${decline.rfq_id}: ${decline.reason}`);
  }

  // Resolve RFQ with best quote
  private resolveRFQ(rfqId: string): void {
    const pending = this.pendingRFQs.get(rfqId);
    if (!pending) return;

    clearTimeout(pending.timeout);

    console.log(`\n🏁 Resolving RFQ ${rfqId}`);
    console.log(`   Quotes received: ${pending.quotes.length}`);
    console.log(`   Declines received: ${pending.declines.length}`);

    if (pending.quotes.length === 0) {
      console.log(`   ❌ No quotes available`);
      pending.resolve(null);
      this.pendingRFQs.delete(rfqId);
      return;
    }

    // Find best quote (highest buy amount for given sell amount)
    const bestQuote = this.selectBestQuote(pending.quotes, pending.request);

    if (!bestQuote) {
      pending.resolve(null);
      this.pendingRFQs.delete(rfqId);
      return;
    }

    console.log(`   ✅ Best quote from: ${bestQuote.maker_id}`);

    // Convert to trader response format
    const response: TraderQuoteResponse = {
      buyAmount: bestQuote.buy_tokens[0]?.amount || "0",
      sellAmount: bestQuote.sell_tokens[0]?.amount || "0",
      price: this.calculatePrice(bestQuote),
      estimatedGas: bestQuote.gas_estimate || "150000",
      maker: bestQuote.maker_address,
      tx: {
        to: bestQuote.maker_address,
        data: "0x", // Market maker should provide signed order data
        value: "0",
        gas: bestQuote.gas_estimate || "150000",
      },
      approvalTarget: bestQuote.maker_address,
      expiry: bestQuote.expiry,
    };

    pending.resolve(response);
    this.pendingRFQs.delete(rfqId);
  }

  // Select best quote based on price
  private selectBestQuote(quotes: QuoteResponse[], request: RFQRequest): QuoteResponse | null {
    if (quotes.length === 0) return null;

    // Sort by best price (most buy tokens for given sell amount)
    const sorted = quotes.sort((a, b) => {
      const aBuy = BigInt(a.buy_tokens[0]?.amount || "0");
      const bBuy = BigInt(b.buy_tokens[0]?.amount || "0");
      return aBuy > bBuy ? -1 : 1; // Descending
    });

    return sorted[0];
  }

  private calculatePrice(quote: QuoteResponse): string {
    const buyAmount = BigInt(quote.buy_tokens[0]?.amount || "0");
    const sellAmount = BigInt(quote.sell_tokens[0]?.amount || "0");

    if (sellAmount === 0n) return "0";

    // Price = buy / sell (as decimal)
    const price = Number(buyAmount) / Number(sellAmount);
    return price.toFixed(6);
  }

  // Get pending RFQ count for monitoring
  public getPendingCount(): number {
    return this.pendingRFQs.size;
  }
}
