#!/usr/bin/env bash
# One-shot bootstrap for a fresh Ubuntu 24.04 droplet hosting the Greek
# market-maker. Idempotent — safe to re-run.
#
#   curl -sSL https://raw.githubusercontent.com/greekfi/protocol/main/market-maker/deploy/bootstrap.sh | bash
#
# Or, after cloning the repo:
#   sudo bash market-maker/deploy/bootstrap.sh
#
# Installs:
#   - Node 25 + corepack (yarn)
#   - PM2 with systemd boot persistence
#   - Caddy with Let's Encrypt auto-TLS
#   - ufw firewall (22/80/443 only)
#
# Prereqs before running:
#   - DNS A record for $MM_DOMAIN points to this droplet (gray-cloud in CF)
#   - You have shell access as root (or with sudo)
#
# After running:
#   1. cp /opt/greek/market-maker/.env.example /opt/greek/market-maker/.env
#      and fill in MAKER_ADDRESS, PRIVATE_KEY, BEBOP_AUTHORIZATION, etc.
#   2. cd /opt/greek/market-maker && pm2 start ecosystem.config.cjs && pm2 save
#   3. Verify: curl https://$MM_DOMAIN/health

set -euo pipefail

MM_DOMAIN="${MM_DOMAIN:-api.greek.finance}"
MM_TLS_EMAIL="${MM_TLS_EMAIL:-admin@greek.finance}"
REPO_URL="${REPO_URL:-https://github.com/greekfi/protocol.git}"
REPO_BRANCH="${REPO_BRANCH:-main}"
INSTALL_DIR="${INSTALL_DIR:-/opt/greek/market-maker}"

log() { echo "==> $*"; }

require_root() {
  if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: must run as root (use sudo)" >&2
    exit 1
  fi
}

install_node() {
  if command -v node >/dev/null && [ "$(node -v | cut -d. -f1 | tr -d v)" -ge 25 ]; then
    log "Node $(node -v) already installed"
  else
    log "Installing Node 25"
    curl -fsSL https://deb.nodesource.com/setup_25.x | bash -
    apt-get install -y nodejs
  fi
  corepack enable
}

install_pm2() {
  if command -v pm2 >/dev/null; then
    log "PM2 $(pm2 -v) already installed"
  else
    log "Installing PM2"
    npm install -g pm2
  fi
  # Generate + enable systemd unit so PM2 survives reboots.
  pm2 startup systemd -u root --hp /root >/dev/null 2>&1 || true
}

install_caddy() {
  if command -v caddy >/dev/null; then
    log "Caddy $(caddy version | head -1) already installed"
  else
    log "Installing Caddy"
    apt-get install -y debian-keyring debian-archive-keyring apt-transport-https curl
    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' \
      | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' \
      | tee /etc/apt/sources.list.d/caddy-stable.list >/dev/null
    apt-get update
    apt-get install -y caddy
  fi
}

configure_caddy() {
  log "Configuring Caddy for $MM_DOMAIN"
  install -d -m 0755 /etc/caddy
  cat > /etc/caddy/Caddyfile.env <<EOF
MM_DOMAIN=$MM_DOMAIN
MM_TLS_EMAIL=$MM_TLS_EMAIL
EOF
  # Use the Caddyfile checked into the repo as the source of truth.
  if [ -f "$INSTALL_DIR/deploy/Caddyfile" ]; then
    cp "$INSTALL_DIR/deploy/Caddyfile" /etc/caddy/Caddyfile
  fi
  # Wire env file into the systemd unit (idempotent override).
  install -d -m 0755 /etc/systemd/system/caddy.service.d
  cat > /etc/systemd/system/caddy.service.d/override.conf <<'EOF'
[Service]
EnvironmentFile=/etc/caddy/Caddyfile.env
EOF
  systemctl daemon-reload
  systemctl enable caddy
  systemctl restart caddy
}

configure_firewall() {
  log "Configuring ufw"
  ufw --force reset >/dev/null 2>&1 || true
  ufw default deny incoming
  ufw default allow outgoing
  ufw allow 22/tcp
  ufw allow 80/tcp
  ufw allow 443/tcp
  ufw --force enable
}

clone_repo() {
  if [ -d "$INSTALL_DIR/.git" ]; then
    log "Repo already cloned at $INSTALL_DIR — fetching latest"
    git -C "$INSTALL_DIR" fetch origin
    git -C "$INSTALL_DIR" reset --hard "origin/$REPO_BRANCH"
  else
    log "Cloning $REPO_URL ($REPO_BRANCH) — sparse checkout of market-maker/"
    install -d -m 0755 "$(dirname "$INSTALL_DIR")"
    git clone --filter=blob:none --sparse --branch "$REPO_BRANCH" "$REPO_URL" "$INSTALL_DIR.tmp"
    git -C "$INSTALL_DIR.tmp" sparse-checkout set market-maker
    mv "$INSTALL_DIR.tmp/market-maker" "$INSTALL_DIR"
    rm -rf "$INSTALL_DIR.tmp"
    # Re-attach as a real git working tree at the subdir level.
    (cd "$INSTALL_DIR" && git init -q && git remote add origin "$REPO_URL" && git fetch -q origin "$REPO_BRANCH" && git checkout -q -B "$REPO_BRANCH" "origin/$REPO_BRANCH" -- || true)
  fi
}

build_app() {
  log "Installing deps + building"
  cd "$INSTALL_DIR"
  yarn install
  yarn build --no-dts
  mkdir -p logs
}

main() {
  require_root
  log "Bootstrapping market-maker on $(hostname) — domain=$MM_DOMAIN"
  apt-get update
  apt-get install -y curl gnupg ca-certificates git ufw
  install_node
  install_pm2
  clone_repo
  build_app
  install_caddy
  configure_caddy
  configure_firewall

  log "Done. Next steps:"
  echo "  1. cp $INSTALL_DIR/.env.example $INSTALL_DIR/.env && \$EDITOR $INSTALL_DIR/.env"
  echo "  2. cd $INSTALL_DIR && pm2 start ecosystem.config.cjs && pm2 save"
  echo "  3. curl https://$MM_DOMAIN/health"
}

main "$@"
