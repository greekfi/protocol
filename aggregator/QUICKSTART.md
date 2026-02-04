# Quick Start Guide

## What You Built

A complete RFQ aggregator system that routes quotes between traders and market makers, similar to Bebop but without token restrictions.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                                                             │
│  TRADER (Frontend at localhost:3000)                        │
│                                                             │
└──────────────────┬──────────────────────────────────────────┘
                   │ HTTP GET /quote
                   ↓
┌─────────────────────────────────────────────────────────────┐
│                                                             │
│  AGGREGATOR (This Package - localhost:3002)                │
│                                                             │
│  • Receives RFQ from trader                                 │
│  • Broadcasts to connected market makers                    │
│  • Collects quotes (5 second timeout)                       │
│  • Returns best quote to trader                             │
│                                                             │
└──────────────────┬──────────────────────────────────────────┘
                   │ WebSocket
                   │ ws://localhost:3003
                   ↓
┌─────────────────────────────────────────────────────────────┐
│                                                             │
│  MARKET MAKER(S) (RFQ Package)                              │
│                                                             │
│  • Connects to aggregator via WebSocket                     │
│  • Registers supported tokens                               │
│  • Receives RFQs                                            │
│  • Responds with quotes or declines                         │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

## Running Everything

### Step 1: Start the Aggregator (Terminal 1)

```bash
cd aggregator
yarn dev
```

You should see:
```
🔌 Market Maker WebSocket server listening on port 3003
🌐 Trader API listening on http://localhost:3002

Waiting for market makers to connect...
```

### Step 2: Start Market Maker(s) (Terminal 2)

```bash
cd rfq
yarn dev:aggregator
```

You should see:
```
Connecting to aggregator at ws://localhost:3003...
✅ Connected to aggregator
📝 Registering with aggregator...
✅ Successfully registered with aggregator
```

The aggregator should show:
```
✅ Registered market maker: Option Market Maker (maker-001)
   Supported tokens: 13
```

### Step 3: Start the Frontend (Terminal 3)

```bash
yarn start
```

Navigate to http://localhost:3000/trade

## Testing the Flow

1. **Select a token** from the dropdown (e.g., WETH)
2. **Select an option** from the grid
3. **Enter an amount** (default is 1)
4. **Watch the console** - you should see:

**Frontend console:**
```
📞 Requesting quote from aggregator
   Params: buy_tokens=0x...&sell_tokens=0x...
✅ Aggregator response: {...}
```

**Aggregator console:**
```
📞 Quote request from 0x...
📡 Broadcast RFQ {uuid} to 1 market makers
💰 Quote 1 received for RFQ {uuid}
✅ Best quote from: maker-001
```

**Market Maker console:**
```
📨 RFQ received: {uuid}
✅ Sent quote to aggregator
```

5. **See the quote** display in the UI with buy/sell amounts

## Troubleshooting

### "No market makers available for these tokens"
- Make sure the RFQ market maker is running
- Check that the token address matches one in `rfq/src/optionsList.ts`

### "No quotes received from market makers"
- Check market maker console for errors
- Verify the RFQ handler is running
- Check token addresses are lowercase in comparison

### Frontend shows "N/A" for amounts
- Check browser console for the aggregator response
- The response format should match `TraderQuoteResponse` type
- Verify `buyAmount` and `sellAmount` fields exist

## Adding More Market Makers

You can run multiple market makers:

**Terminal 4:**
```bash
cd rfq
MAKER_ID=maker-002 MAKER_NAME="Another MM" yarn dev:aggregator
```

The aggregator will route to both and return the best quote!

## Next Steps

- [ ] Implement actual order execution (currently just returns quote)
- [ ] Add signature verification
- [ ] Add settlement tracking
- [ ] Add maker reputation/scoring
- [ ] Add advanced routing algorithms
- [ ] Add monitoring/metrics
