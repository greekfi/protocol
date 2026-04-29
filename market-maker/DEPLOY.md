# Market-maker Deployment

Deployed to **[Fly.io](https://fly.io)** as a single Docker container running
all four PM2 processes (`direct`, `relay`, `bebop`, `deribit`). Caddy inside
the container path-routes the public ports to the right service.

```
Browser
   │  https/wss://api.greek.finance
   ▼
Fly edge ──TLS terminate──▶ VM port 8080 ──Caddy──▶ /pricing  → :3004 (relay WS)
                                                     /rfq      → :3011 (direct WS)
                                                     *         → :3010 (direct HTTP)
                                                     ▲
                                                     │  PM2 manages 4 procs
                                                     │  inside the same VM:
                                                     │   • direct  — HTTP+WS quotes
                                                     │   • relay   — Bebop fan-out
                                                     │   • bebop   — Bebop maker
                                                     │   • deribit — IV source
```

App: **`greek-protocol`** at `https://greek-protocol.fly.dev`. Custom domain
**`api.greek.finance`** is added as a Fly cert (see `Custom domain` below).

## Files

- `Dockerfile` — multi-stage build (yarn install + tsup build → caddy + pm2 runtime)
- `.dockerignore` — whitelists only the market-maker workspace + workspace metadata
- `market-maker/fly.toml` — Fly app config
- `market-maker/deploy/Caddyfile` — internal path routing (no TLS, Fly handles it)
- `market-maker/deploy/entrypoint.sh` — starts caddy + pm2-runtime
- `market-maker/ecosystem.config.cjs` — PM2 process definitions

## Deploy

**Automatic:** push to `main` with changes under `market-maker/**`,
`Dockerfile`, or `core/abi/**` triggers `.github/workflows/deploy-mm.yml`,
which runs `flyctl deploy --remote-only`. Concurrency-guarded: one deploy at a time.

**Manual:**

```bash
# From repo root
fly deploy --config market-maker/fly.toml
```

`fly deploy` builds remotely on Fly's builder by default (no local Docker
required), pushes the image to Fly's registry, then rolls the machine.

## Required GitHub secret

| Secret | How to get it |
|---|---|
| `FLY_API_TOKEN` | `fly tokens create deploy --app greek-protocol` and paste the value |

That's it — no SSH keys, no host secrets. Fly is the only auth boundary.

## Secrets (runtime env vars)

Set sensitive vars with `fly secrets`:

```bash
fly secrets import --app greek-protocol <<EOF
PRIVATE_KEY=0x...
MAKER_ADDRESS=0x...
BEBOP_MARKETMAKER=...
BEBOP_AUTHORIZATION=...
EOF
```

Non-sensitive vars live in `[env]` of `fly.toml` — committed to the repo.

To see what's set: `fly secrets list --app greek-protocol` (digest-only, never values).

To rotate: `fly secrets set KEY=newvalue` then `fly deploy` (a secret change
triggers a rolling restart of the VM by default).

## Custom domain (api.greek.finance)

```bash
# Add the cert (Fly issues + auto-renews via Let's Encrypt)
fly certs add api.greek.finance --app greek-protocol

# fly will print which DNS records to set. Typically:
#   CNAME api.greek.finance → greek-protocol.fly.dev
# Cloudflare: gray-cloud the record (Fly issues its own cert).

# Verify (~30s after DNS propagates):
fly certs show api.greek.finance --app greek-protocol
```

## Switching pricing modes (bebop ↔ deribit)

Both share Bebop's WebSocket — only one can run at a time. The default
ecosystem.config.cjs has `bebop` set to `autostart: false`. To switch on the
fly machine:

```bash
fly ssh console --app greek-protocol --command 'pm2 stop deribit && pm2 start bebop'
fly ssh console --app greek-protocol --command 'pm2 stop bebop && pm2 start deribit'
```

(The change persists for the lifetime of the machine — a redeploy resets to
the ecosystem.config.cjs defaults.)

## Operations

```bash
# App status
fly status --app greek-protocol

# Tail logs (all processes)
fly logs --app greek-protocol

# SSH into the VM
fly ssh console --app greek-protocol

# Inside the VM
pm2 list
pm2 logs --lines 50
pm2 logs direct --lines 30

# Restart everything
fly machine restart --app greek-protocol

# Rollback to a previous release
fly releases --app greek-protocol
fly deploy --image registry.fly.io/greek-protocol:deployment-<id> --config market-maker/fly.toml
```

## Frontend wiring

Vercel project env vars (Production + Preview):

| Variable | Value |
|---|---|
| `NEXT_PUBLIC_DIRECT_API_URL` | `https://api.greek.finance` |
| `NEXT_PUBLIC_RFQ_API_URL` | `https://api.greek.finance` |
| `NEXT_PUBLIC_PRICING_WS_URL` | `wss://api.greek.finance/pricing` |
| `NEXT_PUBLIC_RFQ_WS_URL` | `wss://api.greek.finance/rfq` |

`NEXT_PUBLIC_*` vars bake at build time — **redeploy** Vercel after changing.

## Why Fly.io and not Caddy-on-a-droplet

The previous setup was nginx/Caddy + PM2 on a $6 DigitalOcean droplet, with
a hand-rolled bootstrap script, GH Actions tarball flow, and an env-render
script. Three reasons we moved off it:

1. **TLS** — Fly issues + renews Let's Encrypt automatically. Zero config.
2. **WS support** — Fly's edge proxies WebSocket upgrades on standard ports
   (no Cloudflare port whitelist gymnastics).
3. **Deploy is `fly deploy`** — no SSH, no `pm2 reload`, no env-file scping.
   Image build + atomic machine swap, all managed.

Cost is similar (~$5-8/mo on shared-cpu-1x@512MB) and the deploy code surface
shrunk from ~600 lines of bash + YAML to ~150 lines of Dockerfile + fly.toml.

## Troubleshooting

**Deploy fails at "build context too large"**
The `.dockerignore` whitelist excludes everything by default. If a new
workspace was added, add its `package.json` to the whitelist (yarn needs all
workspace package.jsons to resolve the graph).

**`/health` check fails after deploy**
`pm2 list` from `fly ssh console` will show which process crashed. Most
common: missing secret. `fly secrets list` to verify.

**Bebop disconnects after 5min idle**
Bebop's WS code reconnects with exponential backoff. If you see this with no
recovery, check the `bebop` process logs — usually a stale auth token.
