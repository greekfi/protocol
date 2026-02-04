"use client";

import React from "react";
import { useClaimFees } from "../hooks/useClaimFees";

const ClaimFeesButton: React.FC = () => {
  const { claimFees, isPending, error } = useClaimFees();

  const handleClaimFees = async () => {
    try {
      await claimFees();
    } catch (error) {
      console.error("Error claiming fees:", error);
    }
  };

  return (
    <button
      onClick={handleClaimFees}
      disabled={isPending}
      className={`px-4 py-2 rounded-lg font-medium transition-all ${
        isPending
          ? "bg-gray-400 cursor-not-allowed opacity-50"
          : "bg-green-600 hover:bg-green-700 text-white cursor-pointer"
      }`}
      title="Claim accumulated fees from all options"
    >
      {isPending ? "⏳ Claiming..." : "💰 Claim Fees"}
    </button>
  );
};

export default ClaimFeesButton;
