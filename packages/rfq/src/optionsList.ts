// Static list of option tokens with their prices
export interface OptionWithPrice {
  address: string;
  type: "CALL" | "PUT";
  bidPrice: string;  // Price we pay (when user sells to us)
  askPrice: string;  // Price we charge (when user buys from us)
  decimals: number;  // Option token decimals (fetched from contract)
  quoteDecimals: number;  // Quote token (USDC) decimals
}

export const OPTIONS_LIST: OptionWithPrice[] = [
  // WETH Puts
  {
    address: "0x2b8280A41252624a34DF30942b06CA2a2aE887c3",
    type: "PUT",
    bidPrice: "5.5",
    askPrice: "5.6",
    decimals: 6,
    quoteDecimals: 6,
  },

  // WETH Calls
];

// Create a map for quick lookup
export const OPTIONS_MAP = new Map(
  OPTIONS_LIST.map(opt => [opt.address.toLowerCase(), opt])
);

export function getOption(address: string): OptionWithPrice | undefined {
  return OPTIONS_MAP.get(address.toLowerCase());
}

export function isOptionToken(address: string): boolean {
  return OPTIONS_MAP.has(address.toLowerCase());
}
