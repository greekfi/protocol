"use client";

import { useState } from "react";
import { parseEther, toHex } from "viem";
import { useAccount, useBalance, useChainId, usePublicClient } from "wagmi";

const TOPUP_ETH = 10n;

export function EthFaucet() {
  const { address } = useAccount();
  const chainId = useChainId();
  const publicClient = usePublicClient();
  const { refetch: refetchBalance } = useBalance({ address });

  const [status, setStatus] = useState<"idle" | "working" | "success">("idle");

  const isLocalhost = chainId === 31337;
  if (!isLocalhost) return null;

  const handleTopUp = async () => {
    if (!address || !publicClient) return;

    try {
      setStatus("working");
      const current = await publicClient.getBalance({ address });
      const next = current + parseEther(TOPUP_ETH.toString());
      await publicClient.request({
        method: "anvil_setBalance" as any,
        params: [address, toHex(next)] as any,
      });
      await refetchBalance();
      setStatus("success");
      setTimeout(() => setStatus("idle"), 2000);
    } catch (err) {
      console.error("anvil_setBalance failed:", err);
      setStatus("idle");
    }
  };

  const label =
    status === "success" ? "✓ Funded" : status === "working" ? "Funding..." : `🚰 Get ${TOPUP_ETH} ETH`;

  return (
    <button
      onClick={handleTopUp}
      disabled={!address || status === "working"}
      className={`px-3 py-1.5 rounded text-sm font-medium transition-colors ${
        !address || status === "working"
          ? "bg-gray-700 cursor-not-allowed text-gray-400"
          : status === "success"
            ? "bg-green-600 text-white"
            : "bg-sky-500 hover:bg-sky-600 text-black"
      }`}
    >
      {label}
    </button>
  );
}

export default EthFaucet;
