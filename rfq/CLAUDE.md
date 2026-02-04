# CLAUDE.md - Bebop PMM RFQ Integration

This file provides guidance to Claude Code when working with the Bebop Private Market Maker (PMM) RFQ integration for options trading.

## Project Overview

This package implements a **Request-for-Quote (RFQ) market maker** for option tokens on Bebop, a decentralized exchange aggregator. It provides liquidity for 13 option contracts (7 WETH puts and 6 WETH calls) by:

1. **Streaming continuous pricing** to Bebop via WebSocket (Protobuf format)
2. **Responding to RFQ requests** with buy/sell quotes
3. **Providing an HTTP API** for direct quote requests

## Architecture

### Core Components

#### 1. **Bebop Client** ([src/client.ts](src/client.ts))
- WebSocket client for RFQ communication
- Handles incoming RFQ requests from Bebop
- Sends quote/decline responses
- Auto-reconnection with exponential backoff
- Heartbeat monitoring

#### 2. **Pricing WebSocket** ([src/index.ts](src/index.ts))
- Separate WebSocket connection for streaming prices
- Uses Protobuf binary format (required by Bebop)
- Sends pricing updates every 5 seconds (min: 0.4s)
- Auto-reconnects on disconnect

#### 3. **Options List** ([src/optionsList.ts](src/optionsList.ts))
- Static list of 13 option contracts with bid/ask prices
- Currently: bid $0.04, ask $0.05 for all options
- Maps option addresses to pricing information

#### 4. **HTTP API Server** ([src/api.ts](src/api.ts))
- Express server on port 3001
- `/quote` endpoint for direct quote requests
- CORS enabled for frontend integration

### File Structure

```
packages/rfq/
├── src/
│   ├── index.ts              # Main entry point, pricing WebSocket
│   ├── client.ts             # Bebop RFQ WebSocket client
│   ├── types.ts              # TypeScript type definitions
│   ├── optionsList.ts        # Static option contracts and prices
│   ├── api.ts                # HTTP API server
│   ├── pricing.proto         # Protobuf schema for pricing messages
│   ├── pricing_pb.js         # Generated Protobuf code (static)
│   └── pricing_pb.d.ts       # TypeScript definitions for Protobuf
├── package.json
├── tsconfig.json
├── CLAUDE.md                 # This file
└── README.md
```

## Development Commands

### Running the Service

```bash
# Start with hot reload (default: Ethereum)
yarn dev

# Start on specific chain
CHAIN=base yarn dev
CHAIN=ethereum yarn dev

# Production mode
yarn start
yarn start:aggregator  # Alternative aggregator implementation
```

### Building

```bash
yarn build              # Compile TypeScript to dist/
```

### Regenerating Protobuf Code

When [pricing.proto](src/pricing.proto) changes:

```bash
# Generate JavaScript code
yarn pbjs -t static-module -w commonjs -o src/pricing_pb.js src/pricing.proto

# Generate TypeScript definitions
yarn pbts -o src/pricing_pb.d.ts src/pricing_pb.js
```

## Protobuf Implementation

### Why Protobuf?

Bebop's pricing endpoint **requires** Protobuf format. JSON is deprecated and will close the WebSocket connection.

### Schema Structure ([pricing.proto](src/pricing.proto))

```protobuf
message LevelInfo {
  bytes base_address = 1;         // Option token address
  uint32 base_decimals = 2;       // 18 for option tokens
  bytes quote_address = 3;        // USDC address
  uint32 quote_decimals = 4;      // 6 for USDC
  repeated double bids = 5;       // [price, amount, price, amount, ...]
  repeated double asks = 6;       // [price, amount, price, amount, ...]
}

message LevelMsg {
  repeated LevelInfo levels = 1;  // All option levels
  bytes maker_address = 2;        // Market maker address
}

message LevelsSchema {
  uint32 chain_id = 1;            // Network ID (e.g., 8453 for Base)
  string msg_topic = 2;           // "pricing"
  string msg_type = 3;            // "update"
  LevelMsg msg = 4;               // Nested message content
}
```

### Building Protobuf Messages

**Key Implementation Pattern** ([index.ts:145-180](src/index.ts#L145-L180)):

```typescript
// Import generated types
import { bebop } from "./pricing_pb";
const { LevelsSchema, LevelMsg, LevelInfo } = bebop;

// Build message using constructor and direct property assignment
const levelsSchema = new LevelsSchema();
levelsSchema.chainId = 8453;           // camelCase properties
levelsSchema.msgTopic = "pricing";
levelsSchema.msgType = "update";
levelsSchema.msg = new LevelMsg();
levelsSchema.msg.makerAddress = hexToBytes(MAKER_ADDRESS);
levelsSchema.msg.levels = [];

// Add levels
for (const option of OPTIONS_LIST) {
  const levelInfo = new LevelInfo();
  levelInfo.baseAddress = hexToBytes(option.address);
  levelInfo.baseDecimals = 18;
  levelInfo.quoteAddress = hexToBytes(USDC_ADDRESS);
  levelInfo.quoteDecimals = 6;

  // Flatten bids/asks: [price, amount, price, amount, ...]
  levelInfo.bids = [];
  levelInfo.bids.push(0.04);   // Price in USD
  levelInfo.bids.push(1000.0); // Amount in whole tokens

  levelInfo.asks = [];
  levelInfo.asks.push(0.05);
  levelInfo.asks.push(1000.0);

  levelsSchema.msg.levels.push(levelInfo);
}

// Encode to binary
const buffer = LevelsSchema.encode(levelsSchema).finish();
pricingWs.send(buffer);
```

**Critical Notes**:
- Use **static generated code** from `pricing_pb.js` (not runtime reflection)
- Properties are **camelCase** (e.g., `chainId`, not `chain_id`)
- Build messages with `new` constructors and direct assignment
- Addresses must be `Buffer` (use `hexToBytes()` helper)
- Bids/asks are **flat arrays**: `[price, amount, price, amount, ...]`
- Message size: ~1163 bytes for 13 options
- Success response: `"websocketsuccess" "Message processed successfully"`

## RFQ Quote Logic

### Quote Flow ([index.ts:197-342](src/index.ts#L197-L342))

1. **Receive RFQ** from Bebop via WebSocket
2. **Identify token direction**:
   - User buying options from us → Use **ask price** ($0.05)
   - User selling options to us → Use **bid price** ($0.04)
3. **Calculate amounts**:
   ```typescript
   // For buying options (user pays USDC, gets options)
   const pricePerOption = BigInt(Math.floor(askPrice * 1e6)); // USDC has 6 decimals
   const usdcNeeded = (optionAmount * pricePerOption) / 1000000000000000000n;

   // For selling options (user gives options, gets USDC)
   const usdcToGive = (optionAmount * pricePerOption) / 1000000000000000000n;
   ```
4. **Return quote** with 30-second expiry

### Price Calculations

**Key Formula**:
```
USDC amount = (option amount in wei * price in USD * 10^6) / 10^18
```

Example:
- User wants 10 option tokens (10 * 10^18 wei)
- Ask price: $0.05 per token
- USDC needed: (10 * 10^18 * 0.05 * 10^6) / 10^18 = 0.5 * 10^6 = 500,000 USDC (6 decimals)

## Environment Variables

Required in `.env`:

```bash
CHAIN=base                              # Chain: ethereum, base, arbitrum, etc.
BEBOP_MARKETMAKER=<your_mm_key>        # Request from Bebop team
BEBOP_AUTHORIZATION=<your_auth_token>  # Request from Bebop team
MAKER_ADDRESS=0x...                    # Your wallet address for signing
```

## Configuration

### Supported Chains

Defined in [index.ts:36-48](src/index.ts#L36-L48):

```typescript
const CHAIN_IDS: Record<Chain, number> = {
  ethereum: 1,
  arbitrum: 42161,
  optimism: 10,
  polygon: 137,
  base: 8453,
  blast: 81457,
  bsc: 56,
  mode: 34443,
  scroll: 534352,
  taiko: 167000,
  zksync: 324,
};
```

### Option Contracts

All options use:
- **Base token**: Option contract (18 decimals)
- **Quote token**: USDC on Base `0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913` (6 decimals)
- **Current pricing**: Bid $0.04, Ask $0.05

Options list: 7 WETH puts + 6 WETH calls (see [optionsList.ts](src/optionsList.ts))

### API Endpoints

**Bebop WebSocket URLs**:
- RFQ: `wss://api.bebop.xyz/pmm/{chain}/v3/maker/quote`
- Pricing: `wss://api.bebop.xyz/pmm/{chain}/v3/maker/pricing?format=protobuf`

**Local HTTP API**:
- Quote endpoint: `http://localhost:3001/quote`

## Pricing Function

### Dynamic Pricing Hook ([index.ts:52-58](src/index.ts#L52-L58))

```typescript
function getOptionPrice(optionAddress: string): number {
  const option = getOption(optionAddress);
  if (!option) return 0;

  // Return ask price for our pricing stream
  return parseFloat(option.askPrice);
}
```

**Future Enhancements**:
This function is the hook for implementing dynamic pricing based on:
- Time to expiration
- Implied volatility
- Inventory levels
- Market conditions
- Greeks (delta, gamma, theta, vega)

Example enhancement:
```typescript
function getOptionPrice(optionAddress: string): number {
  const option = getOption(optionAddress);
  if (!option) return 0;

  const basePrice = parseFloat(option.askPrice);

  // Adjust for time decay
  const timeToExpiry = getTimeToExpiry(optionAddress);
  const thetaAdjustment = calculateTheta(timeToExpiry);

  // Adjust for volatility
  const ivAdjustment = getImpliedVolatility(optionAddress);

  // Adjust for inventory
  const inventoryAdjustment = getInventorySkew(optionAddress);

  return basePrice * (1 + thetaAdjustment + ivAdjustment + inventoryAdjustment);
}
```

## Common Development Tasks

### Adding New Option Contracts

1. Add to [optionsList.ts](src/optionsList.ts):
```typescript
{
  address: "0x...",
  type: "CALL" | "PUT",
  bidPrice: "0.04",
  askPrice: "0.05"
}
```

2. Restart service - pricing will automatically include new option

### Changing Prices

Update `bidPrice` and `askPrice` in [optionsList.ts](src/optionsList.ts). Changes take effect on next pricing update (~5 seconds).

### Testing Quotes Locally

```bash
# Via HTTP API
curl -X POST http://localhost:3001/quote \
  -H "Content-Type: application/json" \
  -d '{
    "buyToken": "0xDdDAE8aB9ff47f9dB15Cf1EC3AC80Ff88b55bF2C",
    "sellToken": "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913",
    "buyAmount": "1000000000000000000"
  }'
```

### Debugging Protobuf Messages

Add logging in [sendPricingUpdate()](src/index.ts#L139-L190):

```typescript
// Before encoding
console.log("Message structure:", JSON.stringify(levelsSchema, null, 2));

// After encoding
console.log("Encoded bytes:", Array.from(buffer).map(b => b.toString(16)));

// Check responses
pricingWs.on("message", (data) => {
  console.log("Bebop response:", data.toString());
});
```

Expected success response:
```
�B	websocketsuccess""Message processed successfully
```

## Dependencies

### Core Dependencies
- `protobufjs@^8.0.0` - Protobuf encoding/decoding
- `protobufjs-cli@^2.0.0` - Protobuf code generation
- `ws@^8.19.0` - WebSocket client
- `express@^5.2.1` - HTTP API server
- `viem@^2.44.1` - Ethereum utilities
- `dotenv@^16.4.5` - Environment configuration

### Why protobufjs v8?

We use protobufjs v8 (not v7) for:
- Better TypeScript support
- Active maintenance
- Compatibility with latest Node.js

**Note**: There's a peer dependency warning with `protobufjs-cli` (wants v7), but this is safe to ignore. The generated code works perfectly with v8.

## Troubleshooting

### Pricing WebSocket Closes with "Invalid protobuf message"

**Symptoms**: Error code 1007, connection closes immediately after sending

**Causes**:
1. Using JSON instead of Protobuf
2. Incorrect protobuf schema
3. Wrong property names (snake_case vs camelCase)
4. Missing required fields

**Solution**: Regenerate protobuf code and verify message structure matches [pricing.proto](src/pricing.proto)

### Pricing Updates Too Slow

**Bebop requirement**: No faster than 0.4 seconds (400ms) between updates

Current interval: 5 seconds ([index.ts:126-134](src/index.ts#L126-L134))

To adjust:
```typescript
pricingInterval = setInterval(() => {
  sendPricingUpdate();
}, 1000); // 1 second (safe)
```

### RFQ Connection Issues

**Symptoms**: "Breached max connections of 1"

**Cause**: Multiple instances running or previous instance not cleaned up

**Solution**:
```bash
# Kill all running instances
pkill -f "yarn dev"
pkill -f "ts-node src/index.ts"

# Restart
yarn dev
```

### Decimal Conversion Errors

**Remember**:
- Option tokens: 18 decimals
- USDC: 6 decimals
- Prices in USD: floating point
- All BigInt calculations must account for decimals

Example:
```typescript
// WRONG
const usdc = optionAmount * price; // Loses precision

// CORRECT
const usdc = (optionAmount * BigInt(price * 1e6)) / 10n**18n;
```

## Security Considerations

1. **Never commit `.env` file** - contains sensitive credentials
2. **Validate all incoming RFQ requests** - check token addresses, amounts
3. **Set reasonable quote expiries** - currently 30 seconds
4. **Monitor for abnormal request patterns** - rate limiting may be needed
5. **Use signing for production quotes** - currently unsigned (add signature field)

## Production Deployment

### Pre-deployment Checklist

- [ ] Set correct `CHAIN` environment variable
- [ ] Verify `BEBOP_MARKETMAKER` and `BEBOP_AUTHORIZATION` credentials
- [ ] Confirm `MAKER_ADDRESS` is funded and authorized
- [ ] Test quotes on testnet first
- [ ] Monitor logs for errors during initial deployment
- [ ] Set up alerting for WebSocket disconnections
- [ ] Implement quote signing (add `signature` field to quote responses)

### Monitoring

Key metrics to track:
- Pricing WebSocket uptime
- RFQ request volume
- Quote acceptance rate
- Pricing message size
- Response times

### Scaling Considerations

Current implementation is single-threaded. For high volume:
- Add Redis for shared state
- Implement horizontal scaling with load balancer
- Cache option metadata
- Optimize BigInt calculations

## Related Documentation

- [Bebop PMM Docs](https://docs.bebop.xyz/market-makers/pricing-quoting-and-signing/pricing)
- [Bebop API Reference](https://docs.bebop.xyz/bebop/bebop-api-pmm-rfq)
- [Protocol Buffers (Protobuf) Docs](https://protobuf.dev/)
- [protobufjs Documentation](https://github.com/protobufjs/protobuf.js)

## Support

For Bebop-specific issues:
- Contact Bebop team for credentials
- Join Bebop Discord/Telegram
- Check API status page

For protocol issues:
- See main [protocol CLAUDE.md](../../CLAUDE.md)
- Review option contracts in [packages/foundry/](../foundry/)
