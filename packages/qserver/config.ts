import type { WhitelistConfig } from './types'

export const QUOTER_PRIVATE_KEY = '0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80'
export const RFQ_CONTRACT = '0x0000000000000000000000000000000000000000'

export const WHITELIST: Record<number, WhitelistConfig> = {
  31337: {
    tokens: [
      '0x5FbDB2315678afecb367f032d93F642f64180aa3',
      '0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512'
    ],
    quoters: ['http://localhost:8081']
  },
  1301: {
    tokens: [],
    quoters: ['http://localhost:8081']
  }
}

export function getWhitelist(chainId: number): WhitelistConfig | undefined {
  return WHITELIST[chainId]
}
