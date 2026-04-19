# Railway Deployment Guide

This guide covers deploying the market-maker services to Railway.

## Services to Deploy

1. **market-maker-bebop**: Bebop RFQ client (receives quote requests)
2. **market-maker-relay**: Bebop price relay (broadcasts prices to clients)

## Prerequisites

- Railway account ([railway.app](https://railway.app))
- GitHub repo connected to Railway
- Environment variables ready (see below)

## Quick Start

### Step 1: Create Railway Project

1. Go to [railway.app](https://railway.app/new)
2. Click "Deploy from GitHub repo"
3. Select your `greek-web` repository
4. Railway creates a new project

### Step 2: Deploy Bebop Service

1. In your Railway project, click the first service created
2. Go to **Settings** tab:
   - **Service Name**: `market-maker-bebop`
   - **Root Directory**: `market-maker`
   - **Start Command**: `yarn bebop`
3. Go to **Variables** tab and add environment variables (see below)
4. Railway auto-deploys when you save

### Step 3: Deploy Relay Service

1. In same Railway project, click **"+ New"** → **"GitHub Repo"**
2. Select the **same** `greek-web` repository
3. Railway creates a second service
4. Go to **Settings** tab:
   - **Service Name**: `market-maker-relay`
   - **Root Directory**: `market-maker`
   - **Start Command**: `yarn relay`
5. Go to **Variables** tab and add environment variables (see below)
6. Railway auto-deploys when you save

### Step 4: Verify Deployment

Check logs to ensure services are running:
```bash
# Install Railway CLI
npm i -g @railway/cli

# Link to project
railway login
railway link

# View logs
railway logs --service market-maker-bebop
railway logs --service market-maker-relay
```

Or view logs in Railway dashboard → Service → Deployments → View Logs

## Environment Variables

### Common (Both Services)

```bash
# Required
CHAIN_ID=8453
MAKER_ADDRESS=0x...
PRIVATE_KEY=0x...

# Pricing
DEFAULT_IV=0.8
RISK_FREE_RATE=0.05
BID_SPREAD=0.02
ASK_SPREAD=0.02
SPOT_POLL_INTERVAL=30000

# Optional RPC overrides
RPC_ETHEREUM=https://eth.drpc.org
RPC_BASE=https://mainnet.base.org
RPC_ARBITRUM=https://arb1.arbitrum.io/rpc
```

### Bebop Service Only

```bash
BEBOP_MARKETMAKER=xxx
BEBOP_AUTHORIZATION=xxx
BEBOP_API_URL=https://api.bebop.xyz
```

### Relay Service Only

```bash
RELAY_WS_PORT=3004
BEBOP_CHAINS=ethereum,base,arbitrum
```

## Setting Environment Variables in Railway

### Via CLI

```bash
# Set for specific service
railway variables set CHAIN_ID=8453 --service market-maker-bebop
railway variables set PRIVATE_KEY=0x... --service market-maker-bebop

# Set for all services in project
railway variables set CHAIN_ID=8453
```

### Via Dashboard

1. Go to service → Variables tab
2. Click "New Variable"
3. Add key-value pairs
4. Railway auto-deploys on variable changes

## Monitoring

### View Logs

```bash
# CLI
railway logs --service market-maker-bebop
railway logs --service market-maker-relay

# Dashboard
Go to service → Logs tab
```

### Check Service Health

Both services expose WebSocket endpoints:
- **Bebop**: Connects to Bebop's WebSocket (no HTTP endpoint)
- **Relay**: WebSocket server on `$RELAY_WS_PORT` (default 3004)

Railway will automatically assign a public URL to each service.

## Networking

### Internal Communication

If your frontend or other services need to connect to the relay:
- Use Railway's internal networking: `${{Relay.RAILWAY_PRIVATE_DOMAIN}}`
- Or use public domain: `market-maker-relay.up.railway.app`

### External Access

Railway provides public domains automatically:
- Format: `[service-name]-production.up.railway.app`
- Custom domains supported via Railway dashboard

## Troubleshooting

### Build Failures

If Railway fails to detect Node.js:
1. Ensure `nixpacks.toml` is in `market-maker/` directory
2. Or add `package.json` check in Railway settings

### Service Won't Start

Check logs for common issues:
- Missing environment variables
- WebSocket connection failures (Bebop auth)
- RPC endpoint issues

```bash
railway logs --service market-maker-bebop
```

### Port Conflicts

Railway automatically assigns `$PORT` environment variable. If you need to bind to a specific port for WebSocket servers, use:

```typescript
const port = process.env.PORT || process.env.RELAY_WS_PORT || 3004;
```

## Cost Optimization

- **Hobby Plan**: $5/month for 500 hours
- **Pro Plan**: $20/month for unlimited hours
- Both services are lightweight (minimal CPU/memory)

## CI/CD

Railway auto-deploys on:
- Push to `main` branch (default)
- Configure deployment triggers in dashboard

To disable auto-deploy:
```bash
railway service --disable-auto-deploy
```

## Rollbacks

```bash
# View deployment history
railway deployments

# Rollback to previous deployment
railway rollback [deployment-id]
```

## Health Checks

The services don't have HTTP health endpoints by default. Consider adding:

```typescript
// In src/bebop.ts or src/relay.ts
import express from 'express';

const app = express();
app.get('/health', (req, res) => {
  res.json({ status: 'ok', uptime: process.uptime() });
});

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => console.log(`Health check on ${PORT}`));
```

## Resources

- [Railway Docs](https://docs.railway.app)
- [Nixpacks Config](https://nixpacks.com/docs/configuration/file)
- [Railway CLI](https://docs.railway.app/develop/cli)
