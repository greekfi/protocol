// market-maker/src/config/options.ts

export interface OptionDeployment {
  factory: string;
  options: string[];  // Deployed option contract addresses
}

// Option contract addresses per chain
export const OPTIONS: Record<number, OptionDeployment> = {
  // === BASE MAINNET ===
  8453: {
    factory: "0x...",  // OptionFactory address
    options: [
      // Add deployed option addresses here
    ],
  },

  // === UNICHAIN MAINNET ===
  130: {
    factory: "0x...",
    options: [],
  },

  // === UNICHAIN SEPOLIA ===
  1301: {
    factory: "0x...",
    options: [
      // Test options
    ],
  },

  // === ANVIL (LOCAL) ===
  31337: {
    factory: "0x5FbDB2315678afecb367f032d93F642f64180aa3",  // Deterministic address
    options: [],
  },
};

export function getOptionFactory(chainId: number): string {
  const deployment = OPTIONS[chainId];
  if (!deployment) throw new Error(`No options deployed on chain ${chainId}`);
  return deployment.factory;
}

export function getOptionAddresses(chainId: number): string[] {
  return OPTIONS[chainId]?.options ?? [];
}

export function isOptionToken(chainId: number, address: string): boolean {
  const options = getOptionAddresses(chainId);
  return options.some((o) => o.toLowerCase() === address.toLowerCase());
}
