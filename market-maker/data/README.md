# Option Metadata Cache

This directory stores cached option metadata fetched from the blockchain.

## Files

- `metadata-{chainId}.json` - Cached metadata for each chain

## Usage

### Fetch and cache metadata

```bash
# Fetch for default chain (from .env)
yarn fetch-metadata

# Fetch for specific chain
CHAIN_ID=8453 yarn fetch-metadata   # Base
CHAIN_ID=1 yarn fetch-metadata      # Ethereum
CHAIN_ID=1301 yarn fetch-metadata   # Unichain Sepolia
```

### When to refresh

Run `yarn fetch-metadata` when:
- New options are deployed
- The cache is stale (you want fresh on-chain data)
- Switching to a new chain

### File structure

```json
{
  "chainId": 1,
  "timestamp": 1738540800000,
  "count": 28,
  "options": [
    {
      "address": "0x93a8f0E3b2103F2DeeA8EcefD86701b41b7810eA",
      "redemptionAddress": "0x...",
      "strike": 2000,
      "expirationTimestamp": 1735689600,
      "isPut": false,
      "collateralAddress": "0x..."
    }
  ]
}
```

## Performance

Loading from file is ~100x faster than fetching from chain:
- From file: ~5ms for 28 options
- From chain: ~500ms+ for 28 options (batched RPC calls)
