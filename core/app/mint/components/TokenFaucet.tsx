"use client";

import { useState } from "react";
import { useMintTestTokens } from "../hooks/transactions/useMintTestTokens";
import { useAccount, useWaitForTransactionReceipt } from "wagmi";

/**
 * Token Faucet Button - Only visible on localhost (chainId 31337)
 * Mints 1000 StableToken and 1000 ShakyToken to connected wallet
 */
export function TokenFaucet() {
  const { address } = useAccount();
  const { mintTokens, isLocalhost } = useMintTestTokens();

  const [txHashes, setTxHashes] = useState<`0x${string}`[] | null>(null);
  const [status, setStatus] = useState<"idle" | "working" | "success">("idle");

  // Wait for both transactions
  const { isSuccess: tx1Success } = useWaitForTransactionReceipt({
    hash: txHashes?.[0],
    query: { enabled: Boolean(txHashes?.[0]) },
  });

  const { isSuccess: tx2Success } = useWaitForTransactionReceipt({
    hash: txHashes?.[1],
    query: { enabled: Boolean(txHashes?.[1]) },
  });

  // Check if both transactions confirmed
  if (txHashes && tx1Success && tx2Success && status === "working") {
    setStatus("success");
    setTimeout(() => {
      setStatus("idle");
      setTxHashes(null);
    }, 2000);
  }

  // Only show on localhost
  if (!isLocalhost) {
    return null;
  }

  const handleMint = async () => {
    if (!address) return;

    try {
      setStatus("working");
      const hashes = await mintTokens();
      setTxHashes(hashes);
    } catch (err: any) {
      setStatus("idle");
      setTxHashes(null);
    }
  };

  const getButtonText = () => {
    if (status === "success") return "✓ Minted";
    if (status === "working") return "Minting...";
    return "🚰 Get Test Tokens";
  };

  return (
    <button
      onClick={handleMint}
      disabled={!address || status === "working"}
      className={`px-3 py-1.5 rounded text-sm font-medium transition-colors ${
        !address || status === "working"
          ? "bg-gray-700 cursor-not-allowed text-gray-400"
          : status === "success"
            ? "bg-green-600 text-white"
            : "bg-yellow-500 hover:bg-yellow-600 text-black"
      }`}
    >
      {getButtonText()}
    </button>
  );
}

export default TokenFaucet;
