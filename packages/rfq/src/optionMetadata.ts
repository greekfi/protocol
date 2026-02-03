import { createPublicClient, http, formatUnits, type Chain } from "viem";
import * as chains from "viem/chains";
import { OPTION_ADDRESSES } from "./optionsList";

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

// Get chain from env - uses same CHAIN_ID as index.ts
function getChain(): Chain {
  const chainId = process.env.CHAIN_ID ? parseInt(process.env.CHAIN_ID) : 1;
  const chain = Object.values(chains).find((c: any) => c?.id === chainId) as Chain | undefined;
  return chain || chains.mainnet;
}

// Create viem client lazily so env vars are loaded
let _client: ReturnType<typeof createPublicClient> | null = null;

function getClient() {
  if (!_client) {
    const chain = getChain();
    const rpcUrl = process.env.RPC_URL || chain.rpcUrls.default.http[0];
    console.log(`[optionMetadata] Creating RPC client for ${chain.name} (chainId: ${chain.id})`);
    console.log(`[optionMetadata] RPC URL: ${rpcUrl}`);
    _client = createPublicClient({
      chain,
      transport: http(rpcUrl),
    });
  }
  return _client;
}

export async function fetchOptionMetadata(optionAddress: string): Promise<OptionMetadata | null> {
  const cached = metadataCache.get(optionAddress.toLowerCase());
  if (cached) return cached;

  const client = getClient();

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
    const strikeNum = parseFloat(formatUnits(strike, 18));

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

export async function fetchAllOptionMetadata(): Promise<Map<string, OptionMetadata>> {
  console.log(`Fetching metadata for ${OPTION_ADDRESSES.length} options...`);

  // Fetch in batches to avoid rate limiting
  const batchSize = 10;
  for (let i = 0; i < OPTION_ADDRESSES.length; i += batchSize) {
    const batch = OPTION_ADDRESSES.slice(i, i + batchSize);
    await Promise.all(batch.map(addr => fetchOptionMetadata(addr)));
    if (i + batchSize < OPTION_ADDRESSES.length) {
      // Small delay between batches
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
let cachedSpotPrice = 2500; // Default fallback
let lastSpotFetch = 0;

export async function fetchSpotPrice(): Promise<number> {
  const now = Date.now();
  // Cache for 60 seconds
  if (now - lastSpotFetch < 60000) {
    return cachedSpotPrice;
  }

  try {
    // Use CoinGecko API (free, no key needed for basic use)
    const response = await fetch(
      "https://api.coingecko.com/api/v3/simple/price?ids=ethereum&vs_currencies=usd"
    );
    const data = await response.json();
    if (data.ethereum?.usd) {
      cachedSpotPrice = data.ethereum.usd;
      lastSpotFetch = now;
      console.log(`Updated spot price: $${cachedSpotPrice}`);
    }
  } catch (error) {
    console.error("Failed to fetch spot price:", error);
  }

  return cachedSpotPrice;
}

export function getSpotPrice(): number {
  return cachedSpotPrice;
}
