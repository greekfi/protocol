/**
 * On-disk persistence for synced events. One JSON file per
 * (chainId, factory) under `data/`.
 *
 * Schema is JSON-friendly — bigints are serialized as decimal strings, dates
 * as ISO strings — so the file is hand-readable / greppable / diffable.
 */

import { existsSync, mkdirSync, readFileSync, renameSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const HERE = dirname(fileURLToPath(import.meta.url));
const DATA_DIR = join(HERE, "..", "data");

const STORAGE_VERSION = 1;

export interface StoredEvent {
  /** The block this event was emitted in. Decimal-encoded bigint. */
  blockNumber: string;
  /** Tx hash for the emitting transaction. Useful for explorers / reorg checks. */
  txHash: string;
  /** Position within the block — sort key for deterministic ordering. */
  logIndex: number;
  args: {
    collateral: string;
    consideration: string;
    expirationDate: number;
    /** Strike, 18-decimal fixed point. Decimal-encoded bigint. */
    strike: string;
    isPut: boolean;
    isEuro: boolean;
    /** Address of the per-option oracle wrapper, or 0x0…0 if non-settled. */
    oracle: string;
    option: string;
    /** Paired Collateral (short-side) ERC20 address. Same as `redemption()` in legacy code. */
    coll: string;
  };
}

export interface StoredCache {
  version: number;
  chainId: number;
  factory: string;
  /** Deployment block — the floor of any rescan after a cache wipe. */
  deploymentBlock: number;
  /** Highest block this cache has scanned through (inclusive). Decimal bigint. */
  lastBlock: string;
  /** ISO timestamp of the last successful sync write. */
  syncedAt: string;
  events: StoredEvent[];
}

function pathFor(chainId: number, factory: string): string {
  const safe = factory.toLowerCase().replace(/[^a-z0-9x]/g, "");
  return join(DATA_DIR, `events-${chainId}-${safe}.json`);
}

export function loadCache(chainId: number, factory: string): StoredCache | null {
  const path = pathFor(chainId, factory);
  if (!existsSync(path)) return null;
  try {
    const parsed = JSON.parse(readFileSync(path, "utf8")) as StoredCache;
    if (
      parsed.version !== STORAGE_VERSION ||
      parsed.chainId !== chainId ||
      parsed.factory.toLowerCase() !== factory.toLowerCase()
    ) {
      console.warn(
        `[storage] cache at ${path} has mismatched version/chain/factory — discarding (version=${parsed.version} chainId=${parsed.chainId} factory=${parsed.factory})`,
      );
      return null;
    }
    return parsed;
  } catch (err) {
    console.warn(`[storage] failed to read cache at ${path}:`, err instanceof Error ? err.message : err);
    return null;
  }
}

/**
 * Persist atomically: write to a temp file then rename. Avoids leaving a
 * half-written JSON file if the process is killed mid-write.
 */
export function saveCache(cache: StoredCache): void {
  if (!existsSync(DATA_DIR)) mkdirSync(DATA_DIR, { recursive: true });
  const path = pathFor(cache.chainId, cache.factory);
  const tmp = `${path}.tmp`;
  writeFileSync(tmp, JSON.stringify(cache, null, 2));
  renameSync(tmp, path);
}

export function getStoragePath(chainId: number, factory: string): string {
  return pathFor(chainId, factory);
}

export const CURRENT_VERSION = STORAGE_VERSION;
