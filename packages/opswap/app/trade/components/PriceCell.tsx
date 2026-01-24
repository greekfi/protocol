"use client";

import { useQuery } from "@tanstack/react-query";
import { useAccount, useChainId, useReadContract } from "wagmi";
import { formatUnits, parseUnits } from "viem";
import type { TradableOption } from "../hooks/useTradableOptions";

// Simple ERC20 decimals ABI
const erc20DecimalsAbi = [
  {
    type: "function",
    name: "decimals",
    inputs: [],
    outputs: [{ type: "uint8" }],
    stateMutability: "view",
  },
] as const;

// Bebop API endpoints by chain ID
const BEBOP_API_URLS: Record<number, string> = {
  1: "https://api.bebop.xyz/pmm/ethereum/v3",
  130: "https://api.bebop.xyz/pmm/unichain/v3",
  1301: "https://api.bebop.xyz/pmm/unichain/v3",
  11155111: "https://api.bebop.xyz/pmm/sepolia/v3",
  8453: "https://api.bebop.xyz/pmm/base/v3",
};

// USDC addresses by chain ID
const USDC_ADDRESSES: Record<number, string> = {
  1: "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48",
  130: "0x078d782b760474a361dda0af3839290b0ef57ad6",
  1301: "0x078d782b760474a361dda0af3839290b0ef57ad6",
  11155111: "0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238",
  8453: "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913",
};

interface PriceCellProps {
  option: TradableOption;
  label: string;
  onSelect: (option: TradableOption) => void;
}

interface BebopQuoteResponse {
  buyTokens: Record<string, { amount: string; decimals: number }>;
  sellTokens: Record<string, { amount: string; decimals: number }>;
}

async function fetchQuote(
  apiUrl: string,
  buyToken: string,
  sellToken: string,
  sellAmount?: string,
  buyAmount?: string,
  takerAddress?: string,
): Promise<BebopQuoteResponse | null> {
  const sourceName = process.env.NEXT_PUBLIC_BEBOP_MARKETMAKER || "";
  const sourceAuth = process.env.NEXT_PUBLIC_BEBOP_AUTHORIZATION || "";

  const params: Record<string, string> = {
    buy_tokens: buyToken,
    sell_tokens: sellToken,
    taker_address: takerAddress || "0x0000000000000000000000000000000000000001",
    source: sourceName,
    approval_type: "Standard",
    skip_validation: "true",
    gasless: "false",
  };

  if (sellAmount) {
    params.sell_amounts = sellAmount;
  } else if (buyAmount) {
    params.buy_amounts = buyAmount;
  }

  const searchParams = new URLSearchParams(params);
  const url = `${apiUrl}/quote?${searchParams.toString()}`;

  const headers: HeadersInit = {
    "source-auth": sourceAuth,
  };

  try {
    const response = await fetch(url, { headers });
    if (!response.ok) {
      return null;
    }
    const data = await response.json();
    return data;
  } catch {
    return null;
  }
}

export function PriceCell({ option, label, onSelect }: PriceCellProps) {
  const { address: takerAddress } = useAccount();
  const chainId = useChainId();

  const apiUrl = BEBOP_API_URLS[chainId];
  const usdcAddress = USDC_ADDRESSES[chainId];
  const optionAddress = option.optionAddress;

  // Fetch option token decimals
  const { data: optionDecimals } = useReadContract({
    address: optionAddress as `0x${string}`,
    abi: erc20DecimalsAbi,
    functionName: "decimals",
  });

  // Fetch bid and ask prices
  const { data: prices, isLoading } = useQuery({
    queryKey: ["optionPrice", optionAddress, chainId, takerAddress, optionDecimals],
    queryFn: async () => {
      if (!apiUrl || !usdcAddress || !optionAddress || optionDecimals === undefined) {
        return { bid: null, ask: null };
      }

      // Quote for 0.005 option using fetched decimals
      const quoteAmount = parseUnits("0.005", optionDecimals).toString();

      // Bid: sell 0.1 option → get USDC (user sells option)
      const bidQuote = await fetchQuote(
        apiUrl,
        usdcAddress,        // buy USDC
        optionAddress,      // sell option
        quoteAmount,        // sell_amounts
        undefined,
        takerAddress,
      );

      // Ask: buy 0.1 option → pay USDC (user buys option)
      const askQuote = await fetchQuote(
        apiUrl,
        optionAddress,      // buy option
        usdcAddress,        // sell USDC
        undefined,
        quoteAmount,        // buy_amounts
        takerAddress,
      );

      console.log("[PriceCell] bidQuote:", bidQuote);
      console.log("[PriceCell] askQuote:", askQuote);

      // Helper to find token data (case-insensitive address match)
      const findTokenData = (tokens: Record<string, { amount: string; decimals: number }> | undefined, address: string) => {
        if (!tokens) return null;
        const key = Object.keys(tokens).find(k => k.toLowerCase() === address.toLowerCase());
        return key ? tokens[key] : null;
      };

      // Bid = USDC received from buyTokens, multiply by 200 for price per 1 option (1/0.005 = 200)
      const bidUsdcData = findTokenData(bidQuote?.buyTokens, usdcAddress);
      console.log("[PriceCell] bidUsdcData:", bidUsdcData, "usdcAddress:", usdcAddress);
      const bidRaw = bidUsdcData?.amount || null;
      const bidDecimals = bidUsdcData?.decimals || 6;
      const bidPer005 = bidRaw ? parseFloat(formatUnits(BigInt(bidRaw), bidDecimals)) : null;
      const bid = bidPer005 !== null ? (bidPer005 * 200).toFixed(4) : null;

      // Ask = USDC paid from sellTokens, multiply by 200 for price per 1 option (1/0.005 = 200)
      const askUsdcData = findTokenData(askQuote?.sellTokens, usdcAddress);
      console.log("[PriceCell] askUsdcData:", askUsdcData);
      const askRaw = askUsdcData?.amount || null;
      const askDecimals = askUsdcData?.decimals || 6;
      const askPer005 = askRaw ? parseFloat(formatUnits(BigInt(askRaw), askDecimals)) : null;
      const ask = askPer005 !== null ? (askPer005 * 200).toFixed(4) : null;

      console.log("[PriceCell] Final prices - bid:", bid, "ask:", ask);
      return { bid, ask };
    },
    enabled: !!apiUrl && !!usdcAddress && !!optionAddress && optionDecimals !== undefined,
    staleTime: 15_000,
    refetchInterval: 15_000,
    retry: 1,
  });

  if (isLoading) {
    return (
      <div className="text-xs text-gray-500 animate-pulse">
        {label}: ...
      </div>
    );
  }

  const bid = prices?.bid ?? "-";
  const ask = prices?.ask ?? "-";

  return (
    <button
      onClick={() => onSelect(option)}
      className="px-2 py-1 rounded bg-gray-900 hover:bg-blue-900 border border-gray-700 hover:border-blue-500 transition-colors text-xs w-full"
    >
      <span className="text-gray-400">{label}:</span>{" "}
      <span className="text-green-400">{bid}</span>
      <span className="text-gray-500"> / </span>
      <span className="text-red-400">{ask}</span>
    </button>
  );
}
