export interface Order {
  maker: string
  tokenIn: string
  tokenOut: string
  price1e18: bigint
  maxIn: bigint
  minPerFillIn: bigint
  maxPerFillIn: bigint
  deadline: bigint
  nonce: bigint
  makerSellsIn: boolean
  allowedFiller: string
  feeBps: bigint
}

export interface QuoteRequest {
  chainId: number
  tokenIn: string
  tokenOut: string
  amountIn: string
  taker: string
}

export interface QuoteResponse {
  order: Order
  signature: string
  remaining?: string
}

export interface WhitelistConfig {
  tokens: string[]
  quoters: string[]
}
