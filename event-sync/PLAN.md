# Event-Sync — Plan

A standalone service that caches `Factory.OptionCreated` events to disk so the MM
and frontend stop re-scanning ~3M Arbitrum blocks every cold start / page load.

## Why

Today three callers do their own chunked `getLogs` against the public Arbitrum
RPC:

| Caller | Path | Pain |
|---|---|---|
| MM cold start | `market-maker/src/config/metadata.ts` | rate-limit on every restart |
| `/mint` | `core/app/mint/hooks/useOptions.ts` | ~290 chunks × 10k blocks |
| `/trade` + `/yield` | `core/app/trade/hooks/useTradableOptions.ts` | same |

Each runs in isolation. Each is the wrong size for the actual problem (one
event from one contract). Symptom: rate-limit storms during deploys, slow first
paint on `/mint`, redundant RPC traffic.

## What's already in place

`event-sync/` workspace skeleton on `main` (commit `a4599af`):

- `package.json` — `@greek/event-sync`, deps: `viem`, `express`, `cors`, `dotenv`
- `tsconfig.json` + `tsup.config.ts` (ESM, `node20`)
- `src/config.ts` — chain catalog (Arbitrum-only for v1), env-overridable RPC
  URLs (`RPC_ARBITRUM`), sync-interval / log-chunking knobs
- `src/storage.ts` — atomic JSON persistence keyed by `(chainId, factory)`,
  schema carries the full event payload (collateral, consideration, strike,
  isPut, isEuro, oracle)

Nothing is running off this yet. No sync loop, no HTTP server, no callers wired.

## Phase 1 — Finish v1 (single chain, single event)

Estimated: ~250 LOC, half a session.

### 1.1 Write the sync loop — `event-sync/src/sync.ts`

- Load cache via `loadCache(chainId, factory)`.
- `fromBlock = (cache?.lastBlock ?? deploymentBlock) + 1`.
- Build chunks of `LOG_CHUNK_SIZE` (10k), run with `LOG_CONCURRENCY` (2)
  concurrent in-flight requests against `viem.publicClient.getLogs`.
- Append new events; `saveCache` atomically.
- Return `{ added, total, lastBlock }` for logging.
- Single-chain function `syncChain(cfg: ChainConfig & { rpcUrl })`. The boot
  loop iterates the array.

### 1.2 HTTP server — `event-sync/src/server.ts`

- `GET /events?chainId=42161&since=<block>` — return events strictly newer than
  `since` (default 0). Body: `{ chainId, factory, lastBlock, events }`.
- `GET /status` — per-chain sync state: `{ chainId, lastBlock, eventCount, lastSyncAt, lastError? }`.
- `GET /health` — `{ status: "ok", chains: [...] }`.
- CORS open for the frontend.
- `EVENT_SYNC_PORT` env default 3050.

### 1.3 Boot — `event-sync/src/index.ts`

- Read chains via `loadChains()`.
- For each chain: kick off `syncChain` immediately, then `setInterval(syncChain, SYNC_INTERVAL_MS)`.
- Start HTTP server.
- Graceful shutdown on SIGTERM/SIGINT.

### 1.4 Verify locally

- `yarn workspace @greek/event-sync start` — first cold sync should run, populate
  `event-sync/data/events-42161-<factory>.json`, print "synced N events through
  block X".
- `curl localhost:3050/events?chainId=42161` returns JSON.
- Subsequent restarts read cache and only fetch the delta.

### 1.5 Deploy as 4th PM2 service on greek-direct

- Build via `yarn workspace @greek/event-sync build` locally (build OOM'd on
  the 1GB droplet last deploy — same trick: build local, rsync `dist/`).
- Add to `/opt/greek/protocol/market-maker/ecosystem.config.cjs` as
  `event-sync` running `node /opt/greek/protocol/event-sync/dist/index.mjs`.
- `pm2 start event-sync && pm2 save`.
- Verify: `curl localhost:3050/health` returns ok, `data/` populated.

## Phase 2 — Wire the consumers

Each consumer becomes ~10 lines of `fetch` instead of ~80 lines of `getLogs`.

### 2.1 MM — `market-maker/src/config/metadata.ts`

- New env: `EVENT_SYNC_URL` (default `http://localhost:3050`).
- Replace `discoverOptionMetadata`'s chunked `getLogs` with a single `fetch`
  to event-sync.
- Keep the per-option `fetchOptionMetadata` fallback for now (it's the safety
  net if event-sync is down or returns empty).
- Boot logs both: `[discoverOptions] using event-sync at ...` so it's visible
  which path served the result.

### 2.2 Frontend — `core/app/mint/hooks/useOptions.ts` + `core/app/trade/hooks/useTradableOptions.ts`

- New env: `NEXT_PUBLIC_EVENT_SYNC_URL` (default `http://localhost:3050`).
- Both hooks: replace the chunked `getLogs` body with `fetch(URL/events)`,
  parse, return same shape they do today (so callers are untouched).
- Keep the chunked path as a fallback, gated on a try/catch around the fetch
  so a 5xx or unreachable event-sync degrades to the old behavior rather than
  bricking the page.
- Tanstack-query `staleTime` can stay 30s — the underlying data updates
  slowly enough that polling event-sync at the same cadence is fine.

### 2.3 Smoke test

- Stop the cold-scan path (block the public RPC at the OS level for a minute):
  `/mint` should still load, MM should still serve quotes.
- Confirm RPC traffic from the page drops to ~0 for event discovery.

## Phase 3 — Multi-chain (if and when needed)

Currently only Arbitrum has live volume. When Base/mainnet need MM coverage:

- Add chain entries to `event-sync/src/config.ts`:
  - Base 8453, factory `0x...`, deploymentBlock `...`
  - Mainnet 1, factory `0x...`, deploymentBlock `...`
- Set `CHAINS=arbitrum,base,mainnet` env on the droplet.
- One JSON file per chain under `data/`. The HTTP API already takes `chainId`
  as a query param — no API change.

## Phase 4 — Cleanup / hardening

Independent of event-sync, worth doing once:

- **Put-pricing parity test** in `market-maker/src/__tests__/pricer-puts.test.ts`.
  - Register one call and one put on the same strike + expiry.
  - Assert `put - call ≈ K · e^(-rT) - S` (put-call parity within 1%).
  - Catches the double-inversion regression we hit today (commits `6f727fb`
    + `8afa4b0`) the next time someone touches the strike pipeline.
- **Deprecate `fetchOptionMetadata` per-option fallback** once event-sync has
  proven stable. The fallback exists because pre-event-sync, a missed event
  meant a missed option. With event-sync as canonical source, the fallback
  becomes dead code.
- **Memory file refresh** — the deployment notes in
  `~/.claude/projects/.../memory/deployment.md` are 80+ days old:
  reference `greek-mm` (destroyed today), the `web` repo (deprecated), pm2
  process names that have changed. Update to reflect:
  - Single droplet `greek-direct` (`161.35.11.105`)
  - `direct` running off `/opt/greek/protocol/market-maker`
  - Deploy: build local → rsync `dist/` → `pm2 restart`
  - New `event-sync` service alongside.
- **Local-branch cleanup**: `feat/exercise-for-gas` (superseded by
  `v2-updates`) and `feat/site-and-paper-refresh` (merged) can both be
  deleted locally.

## Open questions

- **Should the frontend hit event-sync directly, or go through a CORS-friendly
  Vercel/Edge proxy?** Direct works on localhost; production frontend on
  Vercel calling a DigitalOcean IP needs CORS or a proxy. Probably proxy via
  a Next.js route handler so the frontend has one canonical URL.
- **Should event-sync also index `Option.Settled` / `Option.Claimed`** for the
  /trade history pane and post-expiry settlement-price lookup? Not needed for
  v1, but ~30 LOC each to add when ready (storage already pivots on event
  name).
- **Reorg handling** — Arbitrum reorgs are rare but non-zero. Current cache is
  append-only and assumes finality. For v1 fine; for production-strict, add
  a CONFIRMATIONS guard that only persists events older than N blocks.
