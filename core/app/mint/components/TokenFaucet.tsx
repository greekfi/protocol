"use client";

import { useState } from "react";
import { useMintTestTokens } from "../hooks/transactions/useMintTestTokens";
import { useAccount } from "wagmi";

/**
 * Token Faucet Button — only visible on localhost (chainId 31337).
 * Mints 1000 of each test token that is actually deployed on this chain
 * (StableToken, ShakyToken, and any MockERC20 instances).
 */
export function TokenFaucet() {
  const { address } = useAccount();
  const { mintTokens, isLocalhost, tokens } = useMintTestTokens();

  const [status, setStatus] = useState<"idle" | "working" | "success">("idle");

  if (!isLocalhost) return null;

  const handleMint = async () => {
    if (!address) return;
    try {
      setStatus("working");
      await mintTokens();
      setStatus("success");
      setTimeout(() => setStatus("idle"), 2000);
    } catch (err) {
      console.error("mintTokens failed:", err);
      setStatus("idle");
    }
  };

  const label = (() => {
    if (status === "success") return "✓ Minted";
    if (status === "working") return "Minting...";
    return `🚰 Get Test Tokens${tokens.length ? ` (${tokens.length})` : ""}`;
  })();

  return (
    <button
      onClick={handleMint}
      disabled={!address || status === "working" || tokens.length === 0}
      title={tokens.map(t => t.symbol).join(", ")}
      className={`px-3 py-1.5 rounded text-sm font-medium transition-colors ${
        !address || status === "working" || tokens.length === 0
          ? "bg-gray-700 cursor-not-allowed text-gray-400"
          : status === "success"
            ? "bg-green-600 text-white"
            : "bg-yellow-500 hover:bg-yellow-600 text-black"
      }`}
    >
      {label}
    </button>
  );
}

export default TokenFaucet;
