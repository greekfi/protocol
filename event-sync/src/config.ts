/**
 * Event-sync configuration. Each chain entry binds an RPC URL, the Factory
 * address to scan, and the deployment block (the floor of the cold-start
 * range). Override RPC URLs via env: RPC_<CHAIN_KEY> (e.g. RPC_ARBITRUM).
 */

export interface ChainConfig {
  chainId: number;
  name: string;
  /** Public/free RPC fallback. Real deployments should override via env. */
  defaultRpcUrl: string;
  /** Greek Factory contract on this chain. */
  factory: `0x${string}`;
  /** Block at which the Factory was deployed; cold-scan starting point. */
  deploymentBlock: number;
}

const RAW: ChainConfig[] = [
  {
    chainId: 42161,
    name: "arbitrum",
    defaultRpcUrl: "https://arb1.arbitrum.io/rpc",
    factory: "0x20e84883896c36b52F4Cdefecca5f10140aBf23D",
    deploymentBlock: 454236303,
  },
  // Add Base / mainnet here when their factories are pinned. Multiple chains
  // are supported by design — the sync loop iterates the full list.
];

/** Resolve env-overridden RPC URL per chain. */
function rpcUrlFor(c: ChainConfig): string {
  const key = `RPC_${c.name.toUpperCase()}`;
  return process.env[key] ?? c.defaultRpcUrl;
}

export function loadChains(): Array<ChainConfig & { rpcUrl: string }> {
  const enabled = (process.env.CHAINS ?? "arbitrum").split(",").map(s => s.trim().toLowerCase());
  return RAW.filter(c => enabled.includes(c.name)).map(c => ({ ...c, rpcUrl: rpcUrlFor(c) }));
}

/** HTTP port. Default 3050 leaves room before the MM's 3010/3011. */
export const PORT = parseInt(process.env.EVENT_SYNC_PORT ?? "3050", 10);

/** How often the sync loop fires for each chain. Default 30s — events are
 *  rare (factory createOption), no point hammering RPCs faster. */
export const SYNC_INTERVAL_MS = parseInt(process.env.SYNC_INTERVAL_MS ?? "30000", 10);

/** Per-call getLogs block range cap. Most public RPCs cap at 10k. */
export const LOG_CHUNK_SIZE = 10_000n;

/** Concurrent in-flight getLogs calls during a single sync pass. Keep low to
 *  avoid public-RPC rate limits. */
export const LOG_CONCURRENCY = parseInt(process.env.LOG_CONCURRENCY ?? "2", 10);
