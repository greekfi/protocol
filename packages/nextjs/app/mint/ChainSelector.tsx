import { useState } from "react";
import { getPublicClient } from "./client";
import { availableChains, useChainStore } from "./config";
import { Chain } from "wagmi/chains";

const ChainSelector = () => {
  const { currentChain, setCurrentChain } = useChainStore();
  const [isOpen, setIsOpen] = useState(false);

  const handleChainChange = (chain: Chain) => {
    setCurrentChain(chain);
    setIsOpen(false);

    // Update the client with the new chain
    getPublicClient();

    // Reload the page to reinitialize wagmi with the new chain
    window.location.reload();
  };

  // Chain logos/icons (simplified for now)
  const getChainIcon = (chainId: number) => {
    switch (chainId) {
      case 8453: // Base
        return "🔘";
      case 11155111: // Sepolia
        return "🟣";
      case 1: // Ethereum mainnet
        return "🔷";
      case 42161: // Arbitrum
        return "🔵";
      case 10: // Optimism
        return "🔴";
      case 137: // Polygon
        return "🟢";
      case 98865: // Plume
        return "🟪";
      case 98864: // Plume Testnet
        return "🟪";
      case 84532: //  Base Sepolia
        return "🟣";
      case 1337: // Localhost
        return "🏠";
      case 31337: // Hardhat
        return "🏠";
      default:
        return "⚡";
    }
  };

  return (
    <div className="relative">
      <button
        onClick={() => setIsOpen(!isOpen)}
        className="flex items-center gap-2 bg-black/40 border border-gray-800 rounded-lg px-3 py-2 text-blue-300 hover:bg-black/60 transition-colors"
      >
        <span>{getChainIcon(currentChain.id)}</span>
        <span>{currentChain.name}</span>
        <svg
          className={`w-4 h-4 transition-transform ${isOpen ? "rotate-180" : ""}`}
          fill="none"
          stroke="currentColor"
          viewBox="0 0 24 24"
          xmlns="http://www.w3.org/2000/svg"
        >
          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M19 9l-7 7-7-7"></path>
        </svg>
      </button>

      {isOpen && (
        <div className="absolute mt-2 w-48 bg-black/90 border border-gray-800 rounded-lg shadow-lg z-50">
          <ul className="py-1">
            {availableChains.map(chain => (
              <li key={chain.id}>
                <button
                  onClick={() => handleChainChange(chain)}
                  className={`w-full text-left px-4 py-2 hover:bg-blue-500/20 flex items-center gap-2 ${
                    currentChain.id === chain.id ? "bg-blue-500/10 text-blue-300" : "text-gray-300"
                  }`}
                >
                  <span>{getChainIcon(chain.id)}</span>
                  <span>{chain.name}</span>
                </button>
              </li>
            ))}
          </ul>
        </div>
      )}
    </div>
  );
};

export default ChainSelector;
