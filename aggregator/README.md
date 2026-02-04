# RFQ Aggregator

A middleware service that routes RFQ (Request-for-Quote) requests between traders and market makers.

## Architecture

```
Traders (Frontend)
     ↓ HTTP
     ↓
Aggregator (This Package)
     ↓ WebSocket
     ↓
Market Makers (RFQ Package)
```

## Components

### 1. MarketMakerManager
- WebSocket server for market maker connections
- Handles market maker registration
- Broadcasts RFQs to relevant market makers based on supported tokens
- Collects quotes and declines

### 2. RFQManager
- Creates and manages RFQ requests
- Collects quotes from multiple market makers
- Selects the best quote (highest buy amount for given sell)
- Times out after 5 seconds

### 3. TraderAPI
- HTTP API for traders to request quotes
- GET `/quote` - Request a quote
- GET `/health` - Health check
- GET `/makers` - List connected market makers

## Setup

```bash
# Install dependencies
cd packages/aggregator
yarn install

# Create .env file
cp .env.example .env

# Start the aggregator
yarn dev
```

## Environment Variables

```env
PORT=3002           # HTTP API port
WS_PORT=3003        # WebSocket port for market makers
```

## Running the Full Stack

### Terminal 1: Start Aggregator
```bash
cd packages/aggregator
yarn dev
```

### Terminal 2: Start Market Maker(s)
```bash
cd packages/rfq
yarn dev:aggregator
```

### Terminal 3: Start Frontend
```bash
yarn start
```

## API Endpoints

### POST /quote

Request a quote from market makers.

**Query Parameters:**
- `buy_tokens` - Token address to buy
- `sell_tokens` - Token address to sell
- `sell_amounts` - Amount to sell (in wei)
- `taker_address` - Address of the trader

**Response:**
```json
{
  "buyAmount": "1000000000000000000",
  "sellAmount": "50000",
  "price": "0.000050",
  "estimatedGas": "150000",
  "maker": "0x...",
  "tx": {
    "to": "0x...",
    "data": "0x",
    "value": "0",
    "gas": "150000"
  },
  "approvalTarget": "0x...",
  "expiry": 1234567890
}
```

## Market Maker Protocol

Market makers connect via WebSocket to `ws://localhost:3003` and must:

### 1. Register on connection
```json
{
  "type": "register",
  "maker_id": "maker-001",
  "maker_name": "My Market Maker",
  "maker_address": "0x...",
  "supported_tokens": ["0x...", "0x..."]
}
```

### 2. Respond to RFQs
When receiving an RFQ:
```json
{
  "type": "rfq",
  "rfq_id": "uuid",
  "buy_tokens": [{"token": "0x...", "amount": "1000"}],
  "sell_tokens": [{"token": "0x...", "amount": "50"}],
  "taker_address": "0x..."
}
```

Respond with either a quote:
```json
{
  "type": "quote",
  "rfq_id": "uuid",
  "maker_id": "maker-001",
  "maker_address": "0x...",
  "buy_tokens": [{"token": "0x...", "amount": "1000"}],
  "sell_tokens": [{"token": "0x...", "amount": "45"}],
  "expiry": 1234567890
}
```

Or a decline:
```json
{
  "type": "decline",
  "rfq_id": "uuid",
  "maker_id": "maker-001",
  "reason": "Unsupported token pair"
}
```

## Features

- ✅ WebSocket connections for market makers
- ✅ HTTP API for traders
- ✅ RFQ routing based on supported tokens
- ✅ Quote aggregation with best price selection
- ✅ Automatic reconnection
- ✅ Heartbeat monitoring
- ⏳ Order execution (to be implemented)
- ⏳ Settlement tracking (to be implemented)

## Differences from Bebop

Unlike Bebop's aggregator which:
- Only routes to top 50 liquid tokens
- Requires market maker authorization
- Has proprietary routing algorithms

This aggregator:
- Routes to ANY token (as long as a market maker supports it)
- Open for any market maker to connect
- Simple best-price routing
- Fully transparent and open source
