// modes/bebop.ts
import { Pricer } from "../pricing/pricer";
import { BebopClient } from "../bebop/client";
import { PricingStream } from "../bebop/pricingStream";
import type { RFQRequest } from "../bebop/types";

const USDC_ADDRESSES: Record<number, string> = {
  1: "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48", // Ethereum
  8453: "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913", // Base
  42161: "0xaf88d065e77c8cC2239327C5EDb3A432268e5831", // Arbitrum
};

export async function startBebopMode(pricer: Pricer) {
  const chainId = parseInt(process.env.CHAIN_ID || "1");
  const chain = (process.env.CHAIN || "ethereum") as any;
  const makerAddress = process.env.MAKER_ADDRESS || "0x0000000000000000000000000000000000000000";
  const usdcAddress = USDC_ADDRESSES[chainId] || USDC_ADDRESSES[1];

  // Connect to Bebop RFQ
  const bebopClient = new BebopClient({
    chain,
    chainId,
    marketmaker: process.env.BEBOP_MARKETMAKER!,
    authorization: process.env.BEBOP_AUTHORIZATION!,
    makerAddress,
    privateKey: process.env.PRIVATE_KEY,
  });

  // Set up RFQ handler
  bebopClient.onRFQ(async (rfq: RFQRequest) => {
    return await pricer.handleRfq(rfq);
  });

  await bebopClient.connect();
  console.log("Connected to Bebop RFQ");

  // Start pricing stream
  const pricingStream = new PricingStream(
    {
      chain,
      chainId,
      marketmaker: process.env.BEBOP_MARKETMAKER!,
      authorization: process.env.BEBOP_AUTHORIZATION!,
      makerAddress,
      usdcAddress,
    },
    pricer
  );

  pricingStream.connect();
  console.log("Connected to Bebop Pricing Stream");

  // Graceful shutdown
  const shutdown = () => {
    console.log("\nShutting down Bebop connections...");
    pricingStream.disconnect();
    bebopClient.disconnect();
  };

  process.on("SIGINT", shutdown);
  process.on("SIGTERM", shutdown);
}
