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
    address: "0xDdDAE8aB9ff47f9dB15Cf1EC3AC80Ff88b55bF2C",
    type: "PUT",
    bidPrice: "0.049",
    askPrice: "0.05",
    decimals: 18,
    quoteDecimals: 6,
  },
  {
    address: "0xE06f115CbA094d10727999311AD53c0D77d6177B",
    type: "PUT",
    bidPrice: "0.049",
    askPrice: "0.05",
    decimals: 18,
    quoteDecimals: 6,
  },
  {
    address: "0x0Ca6Ab14D27031dF73AA6263CD5E4d81D16f7b44",
    type: "PUT",
    bidPrice: "0.049",
    askPrice: "0.05",
    decimals: 18,
    quoteDecimals: 6,
  },
  {
    address: "0xF86D1566C18caca2F0eeC067B7a8444d1bd2Ec7E",
    type: "PUT",
    bidPrice: "0.049",
    askPrice: "0.05",
    decimals: 18,
    quoteDecimals: 6,
  },
  {
    address: "0x1E28F701CC7Ee3bB506C562dECa61d6CcdC2F895",
    type: "PUT",
    bidPrice: "0.049",
    askPrice: "0.05",
    decimals: 18,
    quoteDecimals: 6,
  },
  {
    address: "0x554DBC1d93b3e88B382A9B790E09c8C9929AC1C8",
    type: "PUT",
    bidPrice: "0.049",
    askPrice: "0.05",
    decimals: 18,
    quoteDecimals: 6,
  },
  {
    address: "0xb0616C90bFB655744a3B9c9eCCA5Ab513F61D2E0",
    type: "PUT",
    bidPrice: "0.049",
    askPrice: "0.05",
    decimals: 18,
    quoteDecimals: 6,
  },

  // WETH Calls
  {
    address: "0x841CAc6F1Ec913d139F0a76a26f9Ca9841D20CBb",
    type: "CALL",
    bidPrice: "0.049",
    askPrice: "0.05",
    decimals: 18,
    quoteDecimals: 6,
  },
  {
    address: "0x30DE74e407396d02F7475364B07825eC634Ad8cf",
    type: "CALL",
    bidPrice: "0.049",
    askPrice: "0.05",
    decimals: 18,
    quoteDecimals: 6,
  },
  {
    address: "0xa489665b2aA92B6E324f16b6822004228945E346",
    type: "CALL",
    bidPrice: "0.049",
    askPrice: "0.05",
    decimals: 18,
    quoteDecimals: 6,
  },
  {
    address: "0x1cBCe0D0D79751B382E9fe8eCDD18781e052ED38",
    type: "CALL",
    bidPrice: "0.049",
    askPrice: "0.05",
    decimals: 18,
    quoteDecimals: 6,
  },
  {
    address: "0xd054FffB3c02545348b1e4AE4a968C5BaCb5F412",
    type: "CALL",
    bidPrice: "0.049",
    askPrice: "0.05",
    decimals: 18,
    quoteDecimals: 6,
  },
  {
    address: "0x4EF1aD8fc080Ad4c47ef2F6a81B0eeF9E5EF7308",
    type: "CALL",
    bidPrice: "0.049",
    askPrice: "0.05",
    decimals: 18,
    quoteDecimals: 6,
  },
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
