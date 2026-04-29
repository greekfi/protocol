# syntax=docker/dockerfile:1.7

# Multi-stage build for the @greek/market-maker workspace, deployed to Fly.io.
#
#   stage 1 (builder): full yarn workspace + tsup build
#   stage 2 (runtime): node + caddy + pm2 + dist + pruned node_modules

ARG NODE_VERSION=25-alpine

# ─── builder ────────────────────────────────────────────────────────────────
FROM node:${NODE_VERSION} AS builder

WORKDIR /repo

RUN apk add --no-cache python3 make g++ git

# node:25-alpine ships an old yarn 1.x but no corepack. Install corepack and
# let it resolve the project-pinned yarn version (yarn@4.x via packageManager).
RUN npm install -g --force corepack@latest && corepack enable

# Workspace metadata first (better layer cache when lockfile is unchanged).
COPY package.json yarn.lock .yarnrc.yml ./
COPY .yarn ./.yarn
COPY market-maker/package.json market-maker/
# Other workspace members' package.json — yarn requires them to resolve the
# workspace graph, but we only build market-maker.
COPY core/package.json core/
COPY foundry/package.json foundry/

RUN yarn install

# Now bring in just the market-maker sources and build.
COPY market-maker/ market-maker/
RUN yarn workspace @greek/market-maker build --no-dts

# Prune to runtime deps for the runtime stage.
RUN yarn workspaces focus @greek/market-maker --production

# ─── runtime ────────────────────────────────────────────────────────────────
FROM node:${NODE_VERSION} AS runtime

# Caddy for internal path routing; tini for proper PID 1 signal handling.
RUN apk add --no-cache caddy tini ca-certificates curl && \
    npm install -g pm2@latest

WORKDIR /app

# App code + runtime deps.
COPY --from=builder /repo/market-maker/dist ./dist
COPY --from=builder /repo/market-maker/package.json ./package.json
COPY --from=builder /repo/market-maker/ecosystem.config.cjs ./ecosystem.config.cjs
# yarn workspaces use `nmHoistingLimits: workspaces` — runtime deps land inside
# the workspace's own node_modules, not the repo root. Copy that one.
COPY --from=builder /repo/market-maker/node_modules ./node_modules

# Caddy + entrypoint.
COPY market-maker/deploy/Caddyfile /etc/caddy/Caddyfile
COPY market-maker/deploy/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# PM2 needs a logs dir; ecosystem.config.cjs writes there.
RUN mkdir -p /app/logs

# Caddy serves the public port; PM2 services listen on internal-only ports.
EXPOSE 8080

ENV NODE_ENV=production \
    PM2_HOME=/root/.pm2

ENTRYPOINT ["/sbin/tini", "--"]
CMD ["/entrypoint.sh"]
