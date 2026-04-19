import { useState } from "react";
import type { BebopQuote } from "./useBebopQuote";
import { useSendTransaction, useWaitForTransactionReceipt } from "wagmi";

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

      if (!quote.tx) {
        throw new Error("No transaction data in quote");
      }

      setStatus("pending");

      // Execute the signed transaction from Bebop
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
