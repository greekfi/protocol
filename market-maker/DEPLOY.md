# Market-maker Deployment

Deploys to a single DigitalOcean droplet behind Caddy (auto Let's Encrypt TLS),
managed by PM2, redeployed automatically on `main` pushes via GitHub Actions.

```
                  ┌─────────────────────────────────────────────┐
  Browser         │  Droplet                                    │
  ──────► Caddy   │   :80/:443  (TLS, LE certs, auto-renewed)   │
                  │     │                                       │
                  │     ├─ /pricing/*   → ws  localhost:3004    │  relay   (PM2)
                  │     ├─ /rfq/*       → ws  localhost:3011    │  direct  (PM2, ws)
                  │     └─ everything   → http localhost:3010   │  direct  (PM2, http)
                  └─────────────────────────────────────────────┘
```

## First-time droplet setup

Prereqs: a fresh Ubuntu 24.04 droplet, root SSH access, and a DNS A record for
`api.greek.finance` pointing at the droplet IP. **Gray-cloud** in Cloudflare —
proxy off — so the Let's Encrypt HTTP-01 challenge can reach Caddy directly.

```bash
ssh root@<droplet-ip>

# Run the bootstrap (installs Node 25, PM2, Caddy, ufw, clones repo, builds)
curl -sSL https://raw.githubusercontent.com/greekfi/protocol/main/market-maker/deploy/bootstrap.sh | bash

# Fill in secrets
cd /opt/greek/market-maker
cp .env.example .env
$EDITOR .env   # MAKER_ADDRESS, PRIVATE_KEY, BEBOP_*, etc.

# Start
pm2 start ecosystem.config.cjs
pm2 save

# Verify
curl https://api.greek.finance/health
```

Caddy will provision the LE cert on first request — give it ~30 seconds.

## Ongoing deploys (zero-touch)

A push to `main` that touches `market-maker/**` triggers
`.github/workflows/deploy-mm.yml`, which SSHes in, pulls, builds, and PM2-reloads.

**Required GitHub secrets** (Settings → Secrets and variables → Actions):

| Secret | Value |
|---|---|
| `MM_SSH_HOST` | Droplet IP or hostname |
| `MM_SSH_USER` | `root` (or whatever the deploy user is) |
| `MM_SSH_KEY` | Private SSH key whose public half is in `~/.ssh/authorized_keys` on the droplet |

Generate a fresh key for CI:

```bash
ssh-keygen -t ed25519 -C "github-actions-mm-deploy" -f ~/.ssh/mm-deploy
ssh-copy-id -i ~/.ssh/mm-deploy.pub root@<droplet-ip>
# Paste contents of ~/.ssh/mm-deploy (private) into MM_SSH_KEY secret.
```

## Manual deploy

```bash
MM_HOST=root@<droplet-ip> ./scripts/deploy.sh

# Or reload one app only:
MM_HOST=root@<droplet-ip> MM_PM2_APPS="direct" ./scripts/deploy.sh
```

The same script the workflow uses — Just SSH + pull + build + `pm2 reload`.

## PM2 services

Defined in `ecosystem.config.cjs`. All restart on crash, persist across reboots
(`pm2 startup systemd` was wired up by the bootstrap).

| Process | Port | Autostart | Purpose |
|---|---|---|---|
| `direct` | 3010 (HTTP) + 3011 (WS) | yes | `/quote`, `/options`, `/health`, RFQ pricing stream |
| `relay` | 3004 | yes | Bebop taker-price WebSocket fan-out |
| `bebop` | none | **no** | Bebop RFQ maker (start manually) |
| `deribit` | none | yes | Deribit IV-sourced pricing |

`bebop` and `deribit` share the same Bebop WS connection — only one can run
at a time. To switch:

```bash
pm2 stop deribit && pm2 start bebop && pm2 save
```

## Switching pricing modes

```bash
ssh root@<droplet-ip>
pm2 stop deribit && pm2 start bebop && pm2 save     # use Bebop pricing
pm2 stop bebop && pm2 start deribit && pm2 save     # use Deribit pricing
```

`relay` and `direct` keep running across either switch.

## Frontend wiring

Vercel project env vars (Production + Preview):

| Variable | Value |
|---|---|
| `NEXT_PUBLIC_DIRECT_API_URL` | `https://api.greek.finance` |
| `NEXT_PUBLIC_RFQ_API_URL` | `https://api.greek.finance` |
| `NEXT_PUBLIC_PRICING_WS_URL` | `wss://api.greek.finance/pricing` |
| `NEXT_PUBLIC_RFQ_WS_URL` | `wss://api.greek.finance/rfq` |

`NEXT_PUBLIC_*` vars are baked in at build time — **redeploy** after changing.

## Operations

```bash
# Status / logs
ssh root@<droplet-ip> "pm2 list"
ssh root@<droplet-ip> "pm2 logs --lines 50"
ssh root@<droplet-ip> "pm2 logs direct --lines 30"

# Caddy
ssh root@<droplet-ip> "systemctl status caddy"
ssh root@<droplet-ip> "tail -f /var/log/caddy/access.log"
ssh root@<droplet-ip> "caddy reload --config /etc/caddy/Caddyfile"   # after Caddyfile edit

# Restart everything
ssh root@<droplet-ip> "pm2 restart all && systemctl restart caddy"
```

## Troubleshooting

**`ERR_CONNECTION_REFUSED` from the browser**
Cloudflare A record is gray-cloud (correct), but Caddy isn't running or ports
80/443 are blocked. Check `systemctl status caddy` and `ufw status`.

**Cloudflare 521 / 522 / 525**
The A record is orange-cloud (proxied). Either gray-cloud it, or set CF
SSL/TLS mode to **Full (strict)** so CF talks to Caddy over HTTPS.

**LE cert won't issue**
- DNS A record must point to this droplet.
- Port 80 must be open *and* CF must not be proxying (gray-cloud).
- Check `journalctl -u caddy -n 100`.

**`yarn install` fails on droplet**
Old `--immutable` flag bites when deps shifted between commits. The deploy
script uses plain `yarn install`. If you see a Corepack version mismatch,
`corepack enable && corepack prepare yarn@stable --activate` on the droplet.

**Stale local changes blocking deploy**
The deploy script uses `git fetch && git reset --hard` — it discards anything
uncommitted on the droplet. Don't edit code in `/opt/greek/market-maker`.
