import { useState } from "react";
import { encodeFunctionData } from "viem";
import type { BebopQuote } from "./useBebopQuote";
import { useSendTransaction, useWaitForTransactionReceipt } from "wagmi";

// BebopBlend/BebopSettlement v2 — same address across all supported chains.
const BEBOP_SETTLEMENT = "0xbbbbbBB520d69a9775E85b458C58c648259FAD5F" as const;

// Minimal ABI for swapSingle(Order.Single, Signature.MakerSignature, uint256).
// Order.Single has 11 fields; note partner_id lives in packed_commands/elsewhere
// at the contract level (not in this storage struct). flags is a runtime flag
// set and isn't covered by the EIP-712 signature.
const SWAP_SINGLE_ABI = [
  {
    name: "swapSingle",
    type: "function",
    stateMutability: "payable",
    inputs: [
      {
        name: "order",
        type: "tuple",
        components: [
          { name: "expiry", type: "uint256" },
          { name: "taker_address", type: "address" },
          { name: "maker_address", type: "address" },
          { name: "maker_nonce", type: "uint256" },
          { name: "taker_token", type: "address" },
          { name: "maker_token", type: "address" },
          { name: "taker_amount", type: "uint256" },
          { name: "maker_amount", type: "uint256" },
          { name: "receiver", type: "address" },
          { name: "packed_commands", type: "uint256" },
          { name: "flags", type: "uint256" },
        ],
      },
      {
        name: "makerSignature",
        type: "tuple",
        components: [
          { name: "signatureBytes", type: "bytes" },
          { name: "flags", type: "uint256" },
        ],
      },
      { name: "filledTakerAmount", type: "uint256" },
    ],
    outputs: [],
  },
] as const;

export function useBebopTrade() {
  const [status, setStatus] = useState<"idle" | "preparing" | "pending" | "success" | "error">("idle");
  const [error, setError] = useState<string | null>(null);

  const { sendTransactionAsync } = useSendTransaction();
  const [txHash, setTxHash] = useState<`0x${string}` | null>(null);

  const { isSuccess, isError } = useWaitForTransactionReceipt({
    hash: txHash ?? undefined,
  });

  const executeTrade = async (quote: BebopQuote) => {
    try {
      setStatus("preparing");
      setError(null);

      // Direct-quote path: encode swapSingle locally and submit to BebopSettlement.
      if (quote.source === "direct") {
        if (!quote.order || !quote.signature) {
          throw new Error("Direct quote missing order or signature");
        }
        const o = quote.order;
        const data = encodeFunctionData({
          abi: SWAP_SINGLE_ABI,
          functionName: "swapSingle",
          args: [
            {
              expiry: BigInt(o.expiry),
              taker_address: o.taker_address as `0x${string}`,
              maker_address: o.maker_address as `0x${string}`,
              maker_nonce: BigInt(o.maker_nonce),
              taker_token: o.taker_token as `0x${string}`,
              maker_token: o.maker_token as `0x${string}`,
              taker_amount: BigInt(o.taker_amount),
              maker_amount: BigInt(o.maker_amount),
              receiver: o.receiver as `0x${string}`,
              packed_commands: BigInt(o.packed_commands),
              flags: 0n,
            },
            { signatureBytes: quote.signature as `0x${string}`, flags: 0n },
            BigInt(o.taker_amount),
          ],
        });

        setStatus("pending");
        const hash = await sendTransactionAsync({
          to: BEBOP_SETTLEMENT,
          data,
          value: 0n,
        });
        setTxHash(hash);
        return hash;
      }

      // Bebop-API path: they ship pre-encoded calldata.
      if (!quote.tx) {
        throw new Error("No transaction data in quote");
      }

      setStatus("pending");
      const hash = await sendTransactionAsync({
        to: quote.tx.to as `0x${string}`,
        data: quote.tx.data as `0x${string}`,
        value: BigInt(quote.tx.value || "0"),
        gas: BigInt(quote.tx.gas || "0"),
      });
      setTxHash(hash);
      return hash;
    } catch (err: any) {
      setStatus("error");
      setError(err.message || "Transaction failed");
      throw err;
    }
  };

  // Update status based on transaction receipt
  if (txHash && isSuccess && status !== "success") {
    setStatus("success");
  }

  if (txHash && isError && status !== "error") {
    setStatus("error");
    setError("Transaction failed");
  }

  const reset = () => {
    setStatus("idle");
    setError(null);
    setTxHash(null);
  };

  return {
    executeTrade,
    status,
    error,
    txHash,
    reset,
  };
}
