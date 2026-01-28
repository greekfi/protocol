// Option token addresses to filter prices for
// These are the option contract addresses from the RFQ package

export const OPTION_TOKENS: Set<string> = new Set([
  "0x2b8280A41252624a34DF30942b06CA2a2aE887c3",
  "0xa59feE2E6e08bBC8c88CE993947B025C76c62322",
  "0x1284055731C6c4e1C9938247beF2EeB0e2243B03",
  "0xAb68adD4fB153b34eFe05c589d20AcDdE746a1d7",
].map(addr => addr.toLowerCase()));

export function isOptionToken(address: string): boolean {
  return OPTION_TOKENS.has(address.toLowerCase());
}
