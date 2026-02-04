// modes/bebop.ts
import { Pricer } from "../pricing/pricer";
import { BebopClient } from "../bebop/client";
import type { RFQRequest } from "../bebop/types";

export async function startBebopMode(pricer: Pricer) {
  const chainId = parseInt(process.env.CHAIN_ID || "1");
  const chain = (process.env.CHAIN || "ethereum") as any;
  const makerAddress = process.env.MAKER_ADDRESS || "0x0000000000000000000000000000000000000000";

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
}
