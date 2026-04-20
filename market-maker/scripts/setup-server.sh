#!/bin/bash
set -euo pipefail

# First-time server setup for market-maker on a fresh Ubuntu droplet
# Usage: ./scripts/setup-server.sh [host]

HOST="${1:-root@161.35.119.130}"
REMOTE_DIR="/opt/greek/market-maker"
REPO="git@github.com:greekfi/web.git"

echo "==> Setting up $HOST"

ssh "$HOST" bash -s "$REMOTE_DIR" "$REPO" << 'SETUP'
REMOTE_DIR="$1"
REPO="$2"

# Install Node.js 25
if ! command -v node &>/dev/null || [ "$(node -v | cut -d. -f1 | tr -d v)" -lt 25 ]; then
  echo "Installing Node.js 25..."
  curl -fsSL https://deb.nodesource.com/setup_25.x | bash -
  apt-get install -y nodejs
fi

# Enable corepack (for yarn)
corepack enable

# Install PM2 globally
if ! command -v pm2 &>/dev/null; then
  echo "Installing PM2..."
  npm install -g pm2
fi

# Clone repo (sparse checkout for just market-maker/)
if [ ! -d "$REMOTE_DIR" ]; then
  echo "Cloning repo..."
  mkdir -p "$(dirname "$REMOTE_DIR")"
  git clone --filter=blob:none --sparse "$REPO" "$REMOTE_DIR"
  cd "$REMOTE_DIR"
  git sparse-checkout set market-maker
  # Move contents up so market-maker/ is the root
  shopt -s dotglob
  mv market-maker/* . 2>/dev/null || true
  mv market-maker/.* . 2>/dev/null || true
  rmdir market-maker 2>/dev/null || true
else
  echo "Repo already exists at $REMOTE_DIR"
  cd "$REMOTE_DIR"
fi

# Install deps and build
yarn install --immutable
yarn build --no-dts

# Create logs dir
mkdir -p logs

# Set up PM2 startup (survives reboots)
pm2 startup systemd -u root --hp /root 2>/dev/null || true

echo ""
echo "==> Setup complete!"
echo "    1. Copy .env.example to .env and fill in your values:"
echo "       cp $REMOTE_DIR/.env.example $REMOTE_DIR/.env"
echo "    2. Start services:"
echo "       cd $REMOTE_DIR && pm2 start ecosystem.config.cjs"
echo "    3. Save PM2 state:"
echo "       pm2 save"
SETUP
