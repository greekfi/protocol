// @ts-nocheck
export const USDC_TOKEN = {
  address: "0x078D782b760474a361dDA0AF3839290b0EF57AD6" as `0x${string}`,
  decimals: 6,
} as const;

export const ETH_TOKEN = {
  address: "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2" as `0x${string}`,
  decimals: 18,
} as const;

export const HOOKADDRESS = "0xYourHookAddressHere" as `0x${string}`; // Replace with actual hook address
export const UNIVERSAL_ROUTER = "0xEf740bf23aCaE26f6492B10de645D6B98dC8Eaf3" as `0x${string}`; // Uniswap V4 Universal Router
export const PERMIT2_ADDRESS = "0x000000000022d473030f116ddee9f6b43ac78ba3" as `0x${string}`; // Replace with actual Permit2 address
export const ADDRESS = {
  130: {
    tokens: {
      usdc: {
        address: "0x078D782b760474a361dDA0AF3839290b0EF57AD6" as `0x${string}`,
        decimals: 6,
      },
      weth: {
        address: "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2" as `0x${string}`,
        decimals: 18,
      },
    },
    contracts: {
      universalRouter: "0xEf740bf23aCaE26f6492B10de645D6B98dC8Eaf3" as `0x${string}`,
      permit2: "0x000000000022d473030f116ddee9f6b43ac78ba3" as `0x${string}`,
    },
    pricePools: {
      weth: "0x65081CB48d74A32e9CCfED75164b8c09972DBcF1",
    },
  },
};
