import { createPublicClient, http, parseAbiItem, type Address } from "viem";
import { mainnet } from "viem/chains";

const OPTION_CREATED_EVENT = parseAbiItem(
  "event OptionCreated(address indexed collateral, address indexed consideration, uint40 expirationDate, uint96 strike, bool isPut, address indexed option, address redemption)",
);

// Factory address on mainnet
const FACTORY_ADDRESS = "0xeac6035621817b16811395f1f1fa3e3705b0aacd" as Address;
const DEPLOYMENT_BLOCK = 24116718n;

export interface OptionInfo {
  optionAddress: Address;
  redemptionAddress: Address;
  collateral: Address;
  consideration: Address;
  strike: bigint;
  expiration: bigint;
  isPut: boolean;
}

let optionsCache: Map<Address, OptionInfo> = new Map();
let lastFetchTime = 0;
const CACHE_DURATION = 60000; // 1 minute

export async function fetchOptions(): Promise<Map<Address, OptionInfo>> {
  const now = Date.now();

  // Return cache if fresh
  if (now - lastFetchTime < CACHE_DURATION && optionsCache.size > 0) {
    return optionsCache;
  }

  try {
    const rpcUrl = process.env.RPC_URL || undefined;
    const client = createPublicClient({
      chain: mainnet,
      transport: http(rpcUrl),
    });

    // Get current block
    const latestBlock = await client.getBlockNumber();

    // Query in chunks to avoid RPC limits (max 1000 blocks for public RPC)
    const CHUNK_SIZE = 1000n;
    const allLogs: any[] = [];

    let fromBlock = DEPLOYMENT_BLOCK;
    while (fromBlock <= latestBlock) {
      const toBlock = fromBlock + CHUNK_SIZE > latestBlock ? latestBlock : fromBlock + CHUNK_SIZE;

      console.log(`Fetching events from block ${fromBlock} to ${toBlock}...`);

      const logs = await client.getLogs({
        address: FACTORY_ADDRESS,
        event: OPTION_CREATED_EVENT,
        fromBlock,
        toBlock,
      });

      allLogs.push(...logs);
      fromBlock = toBlock + 1n;
    }

    const newCache = new Map<Address, OptionInfo>();

    allLogs.forEach(log => {
      if (!log.args.option) return;

      newCache.set(log.args.option as Address, {
        optionAddress: log.args.option as Address,
        redemptionAddress: log.args.redemption as Address,
        collateral: log.args.collateral as Address,
        consideration: log.args.consideration as Address,
        strike: log.args.strike as bigint,
        expiration: BigInt(log.args.expirationDate as number),
        isPut: log.args.isPut as boolean,
      });
    });

    optionsCache = newCache;
    lastFetchTime = now;

    console.log(`Loaded ${optionsCache.size} option contracts`);
    return optionsCache;
  } catch (error) {
    console.error("Error fetching options:", error);
    return optionsCache; // Return stale cache on error
  }
}

export function isOptionToken(tokenAddress: string): boolean {
  return optionsCache.has(tokenAddress.toLowerCase() as Address);
}

export function getOptionInfo(tokenAddress: string): OptionInfo | undefined {
  return optionsCache.get(tokenAddress.toLowerCase() as Address);
}
