import { useQuery } from "@tanstack/react-query";
import { useAccount, useChainId } from "wagmi";

export interface BebopQuote {
  buyAmount: string;
  sellAmount: string;
  price: string;
  estimatedGas: string;
  tx?: {
    to: string;
    data: string;
    value: string;
    gas: string;
    gasPrice: string;
  };
  approvalTarget?: string;
  routes?: any[];
  source?: "bebop" | "direct";
  // Present when the quote came from our direct server: the signed
  // Order.Single struct + maker signature, ready for BebopSettlement.swapSingle.
  signature?: string;
  signScheme?: "EIP712";
  order?: {
    partner_id: string;
    expiry: string;
    taker_address: string;
    maker_address: string;
    maker_nonce: string;
    taker_token: string;
    maker_token: string;
    taker_amount: string;
    maker_amount: string;
    receiver: string;
    packed_commands: string;
  };
}

interface UseBebopQuoteParams {
  buyToken: string; // Token address to buy
  sellToken: string; // Token address to sell
  sellAmount?: string; // Amount to sell in wei (optional)
  buyAmount?: string; // Amount to buy in wei (optional)
  enabled?: boolean;
}

// Bebop API endpoints by chain ID
const BEBOP_API_URLS: Record<number, string> = {
  1: "https://api.bebop.xyz/pmm/ethereum/v3", // Ethereum Mainnet
  8453: "https://api.bebop.xyz/pmm/base/v3", // Base
  42161: "https://api.bebop.xyz/pmm/arbitrum/v3", // Arbitrum
};

// Polled HTTP fallback — our own market-maker /quote endpoint.
// Same Bebop-compatible response shape; quotes are indicative, not executable.
const DIRECT_API_URL = process.env.NEXT_PUBLIC_DIRECT_API_URL || "http://localhost:3010";

async function fetchDirectQuote(
  buyToken: string,
  sellToken: string,
  takerAddress: string,
  sellAmount?: string,
  buyAmount?: string,
): Promise<BebopQuote | null> {
  const params: Record<string, string> = { buyToken, sellToken, takerAddress };
  if (sellAmount) params.sellAmount = sellAmount;
  else if (buyAmount) params.buyAmount = buyAmount;

  const url = `${DIRECT_API_URL}/quote?${new URLSearchParams(params).toString()}`;
  console.log("📞 Falling back to direct quote server:", url);
  const res = await fetch(url);
  if (!res.ok) throw new Error(`Direct API error: ${res.status} ${res.statusText}`);
  const data = await res.json();
  return { ...data, source: "direct" };
}

export function useBebopQuote({ buyToken, sellToken, sellAmount, buyAmount, enabled = true }: UseBebopQuoteParams) {
  const { address: takerAddress } = useAccount();
  const chainId = useChainId();

  return useQuery<BebopQuote | null>({
    queryKey: ["bebopQuote", buyToken, sellToken, sellAmount, buyAmount, takerAddress, chainId],
    queryFn: async () => {
      if (!takerAddress || !buyToken || !sellToken || (!sellAmount && !buyAmount)) {
        return null;
      }

      // Opt-out: skip Bebop and always hit the local direct server. Useful in dev
      // when Bebop doesn't have liquidity on our option contracts yet.
      if (process.env.NEXT_PUBLIC_USE_DIRECT_QUOTE === "true") {
        return fetchDirectQuote(buyToken, sellToken, takerAddress, sellAmount, buyAmount);
      }

      const bebopApiUrl = BEBOP_API_URLS[chainId];
      if (!bebopApiUrl) {
        return fetchDirectQuote(buyToken, sellToken, takerAddress, sellAmount, buyAmount);
      }

      // Source name and auth from env
      const sourceName = process.env.NEXT_PUBLIC_BEBOP_MARKETMAKER || "";
      const sourceAuth = process.env.NEXT_PUBLIC_BEBOP_AUTHORIZATION || "";

      const params: Record<string, string> = {
        buy_tokens: buyToken,
        sell_tokens: sellToken,
        taker_address: takerAddress,
        source: sourceName,
        // &approval_type=Standard&skip_validation=true&gasless=false&
        approval_type: "Standard",
        skip_validation: "true",
        gasless: "false",
      };

      // Use either sell_amounts or buy_amounts depending on what's provided
      if (sellAmount) {
        params.sell_amounts = sellAmount;
      } else if (buyAmount) {
        params.buy_amounts = buyAmount;
      }

      const searchParams = new URLSearchParams(params);

      console.log("📞 Requesting quote from Bebop");
      console.log("   Source:", sourceName);
      console.log("   Params:", searchParams.toString());

      const url = `${bebopApiUrl}/quote?${searchParams.toString()}`;
      console.log("   URL:", url);

      // Add source-auth header
      const headers: HeadersInit = {
        "source-auth": sourceAuth,
      };
      console.log("   Using source-auth:", sourceAuth.slice(0, 8) + "...");

      try {
        const response = await fetch(url, { headers });
        if (!response.ok) {
          const errorText = await response.text();
          throw new Error(`Bebop API error ${response.status}: ${errorText}`);
        }
        const data = await response.json();
        // Bebop returns 200 with {error: "..."} when no quote is available
        // (missing source/auth, no maker interested, etc.) — treat that as failure.
        // Also treat a zero buyAmount/sellAmount as no-quote (Bebop will happily return
        // "0" for option instruments it doesn't recognize — "0" is truthy in JS, so
        // the plain falsy check above lets it through).
        const buyAmt = BigInt(data?.buyAmount ?? 0);
        const sellAmt = BigInt(data?.sellAmount ?? 0);
        if (data?.error || buyAmt === 0n || sellAmt === 0n) {
          console.warn("⚠️  Bebop returned no usable quote:", data);
          throw new Error(data?.error || "Bebop response has zero buy/sell amount");
        }
        console.log("✅ Bebop response:", data);
        return { ...data, source: "bebop" };
      } catch (err) {
        console.warn("⚠️  Bebop failed, trying direct:", err instanceof Error ? err.message : err);
        return fetchDirectQuote(buyToken, sellToken, takerAddress, sellAmount, buyAmount);
      }
    },
    enabled: enabled && !!takerAddress && !!buyToken && !!sellToken && (!!sellAmount || !!buyAmount),
    staleTime: 15_000, // 15 seconds
    refetchInterval: 15_000, // Refresh every 15 seconds
    retry: 2,
  });
}
