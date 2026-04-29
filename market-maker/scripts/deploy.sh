#!/usr/bin/env bash
# Deploy the market-maker to its droplet.
#
# Pulls the current branch, builds, restarts PM2. Idempotent.
#
# Usage:
#   ./scripts/deploy.sh                       # uses MM_HOST env var
#   ./scripts/deploy.sh root@1.2.3.4          # explicit host
#   MM_HOST=root@1.2.3.4 ./scripts/deploy.sh
#
# Override target dir / branch / app subset:
#   MM_REMOTE_DIR=/opt/greek/market-maker
#   MM_BRANCH=main
#   MM_PM2_APPS="direct relay"   # default: all in ecosystem.config.cjs
#
# CI use: this script is invoked by .github/workflows/deploy-mm.yml.

set -euo pipefail

HOST="${1:-${MM_HOST:-}}"
REMOTE_DIR="${MM_REMOTE_DIR:-/opt/greek/market-maker}"
BRANCH="${MM_BRANCH:-main}"
PM2_APPS="${MM_PM2_APPS:-}"

if [ -z "$HOST" ]; then
  echo "ERROR: pass host as arg or set MM_HOST (e.g. root@1.2.3.4)" >&2
  exit 1
fi

echo "==> Deploying $BRANCH to $HOST:$REMOTE_DIR"

ssh -o StrictHostKeyChecking=accept-new "$HOST" bash -s "$REMOTE_DIR" "$BRANCH" "$PM2_APPS" <<'REMOTE'
set -euo pipefail
REMOTE_DIR="$1"
BRANCH="$2"
PM2_APPS="$3"

cd "$REMOTE_DIR"

echo "==> git fetch && reset --hard origin/$BRANCH"
git fetch origin
git reset --hard "origin/$BRANCH"

echo "==> yarn install + build"
yarn install
yarn build --no-dts

mkdir -p logs

if [ -n "$PM2_APPS" ]; then
  echo "==> pm2 reload $PM2_APPS"
  for app in $PM2_APPS; do
    pm2 reload "$app" --update-env || pm2 start ecosystem.config.cjs --only "$app"
  done
else
  echo "==> pm2 reload ecosystem.config.cjs"
  pm2 reload ecosystem.config.cjs --update-env || pm2 start ecosystem.config.cjs
fi

pm2 save
pm2 list
REMOTE

echo
echo "==> Done. Tail logs: ssh $HOST 'pm2 logs --lines 50'"
