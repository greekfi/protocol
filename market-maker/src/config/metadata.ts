import { formatUnits } from "viem";
import { getOptionAddresses } from "./options";
import { getPublicClient, getCurrentChainId } from "./client";
import { readFileSync, existsSync } from "fs";
import { join, dirname } from "path";
import { fileURLToPath } from "url";

// Option contract ABI (minimal for metadata)
const OPTION_ABI = [
  {
    name: "redemption",
    type: "function",
    stateMutability: "view",
    inputs: [],
    outputs: [{ type: "address" }],
  },
] as const;

// Redemption contract ABI (has the actual option parameters)
const REDEMPTION_ABI = [
  {
    name: "strike",
    type: "function",
    stateMutability: "view",
    inputs: [],
    outputs: [{ type: "uint256" }],
  },
  {
    name: "expirationDate",
    type: "function",
    stateMutability: "view",
    inputs: [],
    outputs: [{ type: "uint40" }],
  },
  {
    name: "isPut",
    type: "function",
    stateMutability: "view",
    inputs: [],
    outputs: [{ type: "bool" }],
  },
  {
    name: "collateral",
    type: "function",
    stateMutability: "view",
    inputs: [],
    outputs: [{ type: "address" }],
  },
] as const;

export interface OptionMetadata {
  address: string;
  redemptionAddress: string;
  strike: number; // In USD (normalized)
  expirationTimestamp: number; // Unix timestamp
  isPut: boolean;
  collateralAddress: string;
}

// Cache for option metadata
const metadataCache = new Map<string, OptionMetadata>();

export async function fetchOptionMetadata(optionAddress: string): Promise<OptionMetadata | null> {
  const cached = metadataCache.get(optionAddress.toLowerCase());
  if (cached) return cached;

  const client = getPublicClient();

  try {
    // First get the redemption contract address
    const redemptionAddress = await client.readContract({
      address: optionAddress as `0x${string}`,
      abi: OPTION_ABI,
      functionName: "redemption",
    } as any) as `0x${string}`;

    // Then get option parameters from redemption contract
    const [strike, expirationDate, isPut, collateral] = await Promise.all([
      client.readContract({
        address: redemptionAddress,
        abi: REDEMPTION_ABI,
        functionName: "strike",
      } as any) as Promise<bigint>,
      client.readContract({
        address: redemptionAddress,
        abi: REDEMPTION_ABI,
        functionName: "expirationDate",
      } as any) as Promise<bigint>,
      client.readContract({
        address: redemptionAddress,
        abi: REDEMPTION_ABI,
        functionName: "isPut",
      } as any) as Promise<boolean>,
      client.readContract({
        address: redemptionAddress,
        abi: REDEMPTION_ABI,
        functionName: "collateral",
      } as any) as Promise<`0x${string}`>,
    ]);

    // Strike is encoded with 18 decimals
    let strikeNum = parseFloat(formatUnits(strike, 18));

    // For puts, the contract stores strike as collateral/consideration (inverted)
    // Normalize to consideration/collateral (same as calls) for Black-Scholes
    if (isPut && strikeNum > 0) {
      strikeNum = 1 / strikeNum;
    }

    const metadata: OptionMetadata = {
      address: optionAddress.toLowerCase(),
      redemptionAddress: redemptionAddress.toLowerCase(),
      strike: strikeNum,
      expirationTimestamp: Number(expirationDate),
      isPut,
      collateralAddress: collateral.toLowerCase(),
    };

    metadataCache.set(optionAddress.toLowerCase(), metadata);
    return metadata;
  } catch (error) {
    console.error(`Failed to fetch metadata for option ${optionAddress}:`, error);
    return null;
  }
}

/**
 * Load option metadata from persisted JSON file
 * This is much faster than fetching from chain
 *
 * @returns Map of option metadata, or null if file doesn't exist
 */
export function loadMetadataFromFile(): Map<string, OptionMetadata> | null {
  const chainId = getCurrentChainId();
  const __filename = fileURLToPath(import.meta.url);
  const __dirname = dirname(__filename);
  const filePath = join(__dirname, "..", "..", "data", `metadata-${chainId}.json`);

  if (!existsSync(filePath)) {
    console.log(`⚠️  No metadata file found at ${filePath}`);
    return null;
  }

  try {
    const fileContent = readFileSync(filePath, "utf-8");
    const data = JSON.parse(fileContent) as {
      chainId: number;
      timestamp: number;
      count: number;
      options: OptionMetadata[];
    };

    if (data.chainId !== chainId) {
      console.warn(`⚠️  Metadata file is for chain ${data.chainId}, but CHAIN_ID is ${chainId}`);
      return null;
    }

    // Populate cache
    const map = new Map<string, OptionMetadata>();
    for (const option of data.options) {
      const address = option.address.toLowerCase();
      map.set(address, option);
      metadataCache.set(address, option);
    }

    const age = Date.now() - data.timestamp;
    const ageMinutes = Math.floor(age / 60000);
    console.log(`✅ Loaded ${data.count} options from file (${ageMinutes}m old)`);

    return map;
  } catch (error) {
    console.error(`❌ Failed to load metadata from file:`, error);
    return null;
  }
}

/**
 * Fetch all option metadata from chain (slow, use loadMetadataFromFile when possible)
 *
 * @param forceRefresh If true, merges cached data with new options from config
 */
export async function fetchAllOptionMetadata(forceRefresh = false): Promise<Map<string, OptionMetadata>> {
  const chainId = getCurrentChainId();
  const optionAddresses = getOptionAddresses(chainId);

  // Load existing cache
  const fromFile = loadMetadataFromFile();

  if (forceRefresh && fromFile) {
    // Merge mode: find options that are in config but not in cache
    const cachedAddresses = new Set(fromFile.keys());
    const configAddresses = new Set(optionAddresses.map(addr => addr.toLowerCase()));

    const newAddresses = optionAddresses.filter(
      addr => !cachedAddresses.has(addr.toLowerCase())
    );

    const removedAddresses = Array.from(cachedAddresses).filter(
      addr => !configAddresses.has(addr)
    );

    if (newAddresses.length === 0 && removedAddresses.length === 0) {
      console.log("✅ Cache is up to date with config");
      return fromFile;
    }

    if (removedAddresses.length > 0) {
      console.log(`🗑️  Removing ${removedAddresses.length} options no longer in config`);
      removedAddresses.forEach(addr => {
        fromFile.delete(addr);
        metadataCache.delete(addr);
      });
    }

    if (newAddresses.length > 0) {
      console.log(`📥 Fetching ${newAddresses.length} new options from chain...`);

      // Fetch new options in batches
      const batchSize = 10;
      for (let i = 0; i < newAddresses.length; i += batchSize) {
        const batch = newAddresses.slice(i, i + batchSize);
        await Promise.all(batch.map(addr => fetchOptionMetadata(addr)));
        if (i + batchSize < newAddresses.length) {
          await new Promise(resolve => setTimeout(resolve, 100));
        }
      }

      console.log(`✅ Successfully fetched ${newAddresses.length} new options`);
    }

    return metadataCache;
  }

  // Non-refresh mode: use cache if available
  if (!forceRefresh && fromFile) {
    return fromFile;
  }

  // No cache available: fetch everything
  console.log(`Fetching metadata for ${optionAddresses.length} options on chain ${chainId}...`);

  const batchSize = 10;
  for (let i = 0; i < optionAddresses.length; i += batchSize) {
    const batch = optionAddresses.slice(i, i + batchSize);
    await Promise.all(batch.map(addr => fetchOptionMetadata(addr)));
    if (i + batchSize < optionAddresses.length) {
      await new Promise(resolve => setTimeout(resolve, 100));
    }
  }

  console.log(`Successfully fetched metadata for ${metadataCache.size} options`);
  return metadataCache;
}

export function getOptionMetadata(address: string): OptionMetadata | undefined {
  return metadataCache.get(address.toLowerCase());
}

// Fetch current ETH spot price from a simple source
// In production, use Chainlink or similar oracle
let cachedSpotPrice = 2300; // Default fallback (update this!)
let lastSpotFetch = 0;

export async function fetchSpotPrice(): Promise<number> {
  const now = Date.now();
  // Cache for 30 seconds
  if (now - lastSpotFetch < 30000 && lastSpotFetch > 0) {
    return cachedSpotPrice;
  }

  // Try CoinGecko first
  try {
    const response = await fetch(
      "https://api.coingecko.com/api/v3/simple/price?ids=ethereum&vs_currencies=usd",
      { signal: AbortSignal.timeout(5000) }
    );
    const data = await response.json() as any;
    if (data.ethereum?.usd) {
      cachedSpotPrice = data.ethereum.usd;
      lastSpotFetch = now;
      console.log(`[CoinGecko] ETH spot price: $${cachedSpotPrice}`);
      return cachedSpotPrice;
    }
  } catch (error) {
    console.error("[CoinGecko] Failed:", (error as Error).message);
  }

  // Fallback to CoinCap
  try {
    const response = await fetch(
      "https://api.coincap.io/v2/assets/ethereum",
      { signal: AbortSignal.timeout(5000) }
    );
    const data = await response.json() as any;
    if (data.data?.priceUsd) {
      cachedSpotPrice = parseFloat(data.data.priceUsd);
      lastSpotFetch = now;
      console.log(`[CoinCap] ETH spot price: $${cachedSpotPrice}`);
      return cachedSpotPrice;
    }
  } catch (error) {
    console.error("[CoinCap] Failed:", (error as Error).message);
  }

  console.warn(`⚠️  Using cached/default spot price: $${cachedSpotPrice}`);
  return cachedSpotPrice;
}

export function getSpotPrice(): number {
  return cachedSpotPrice;
}
