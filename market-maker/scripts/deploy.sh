#!/bin/bash
set -euo pipefail

# Deploy market-maker to DigitalOcean droplet
# Usage: ./scripts/deploy.sh [host]

HOST="${1:-root@161.35.119.130}"
REMOTE_DIR="/opt/greek/market-maker"

echo "==> Deploying to $HOST:$REMOTE_DIR"

# Pull latest code
echo "==> Pulling latest code..."
ssh "$HOST" "cd $REMOTE_DIR && git fetch origin && git reset --hard origin/\$(git rev-parse --abbrev-ref HEAD)"

# Install deps & build
echo "==> Installing dependencies and building..."
ssh "$HOST" "cd $REMOTE_DIR && yarn install && yarn build --no-dts"

# Ensure logs directory exists
ssh "$HOST" "mkdir -p $REMOTE_DIR/logs"

# Restart PM2 processes
echo "==> Restarting PM2 processes..."
ssh "$HOST" "cd $REMOTE_DIR && pm2 restart ecosystem.config.cjs || pm2 start ecosystem.config.cjs"

# Show status
echo ""
echo "==> Status:"
ssh "$HOST" "pm2 list"

echo ""
echo "==> Done. Use 'ssh $HOST \"pm2 logs\"' to tail logs."
