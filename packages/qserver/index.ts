import fastify from 'fastify'
import { createPublicClient, http, isAddress } from 'viem'
import type { QuoteRequest, QuoteResponse, Order } from './types'
import { getWhitelist, RFQ_CONTRACT, getRpcUrl } from './config'

const server = fastify()

// RFQ contract ABI for validateOrder function
const RFQ_ABI = [
  {
    inputs: [
      {
        components: [
          { name: 'maker', type: 'address' },
          { name: 'tokenIn', type: 'address' },
          { name: 'tokenOut', type: 'address' },
          { name: 'price1e18', type: 'uint256' },
          { name: 'maxIn', type: 'uint256' },
          { name: 'minPerFillIn', type: 'uint256' },
          { name: 'maxPerFillIn', type: 'uint256' },
          { name: 'deadline', type: 'uint256' },
          { name: 'nonce', type: 'uint256' },
          { name: 'makerSellsIn', type: 'bool' },
          { name: 'allowedFiller', type: 'address' },
          { name: 'feeBps', type: 'uint256' }
        ],
        name: 'o',
        type: 'tuple'
      },
      { name: 'sig', type: 'bytes' },
      { name: 'filler', type: 'address' }
    ],
    name: 'validateOrder',
    outputs: [{ name: 'remaining', type: 'uint256' }],
    stateMutability: 'view',
    type: 'function'
  }
] as const

async function validateOrderOnChain(
  order: Order,
  signature: string,
  taker: string,
  chainId: number
): Promise<{ valid: boolean; remaining?: bigint }> {
  try {
    const rpcUrl = getRpcUrl(chainId)
    if (!rpcUrl) return { valid: false }

    const client = createPublicClient({
      transport: http(rpcUrl)
    })

    // Cast Order to the format viem expects
    const orderForContract = {
      maker: order.maker as `0x${string}`,
      tokenIn: order.tokenIn as `0x${string}`,
      tokenOut: order.tokenOut as `0x${string}`,
      price1e18: order.price1e18,
      maxIn: order.maxIn,
      minPerFillIn: order.minPerFillIn,
      maxPerFillIn: order.maxPerFillIn,
      deadline: order.deadline,
      nonce: order.nonce,
      makerSellsIn: order.makerSellsIn,
      allowedFiller: order.allowedFiller as `0x${string}`,
      feeBps: order.feeBps
    }

    const remaining = await client.readContract({
      address: RFQ_CONTRACT as `0x${string}`,
      abi: RFQ_ABI,
      functionName: 'validateOrder',
      args: [orderForContract, signature as `0x${string}`, taker as `0x${string}`]
    })

    return { valid: true, remaining }
  } catch (error) {
    return { valid: false }
  }
}

server.post<{ Body: QuoteRequest }>('/rfq', async (request, reply) => {
    const { chainId, tokenIn, tokenOut, amountIn, taker } = request.body

    if (!isAddress(tokenIn) || !isAddress(tokenOut) || !isAddress(taker)) {
        return reply.code(400).send({ error: 'Invalid address' })
    }

    if (!amountIn || BigInt(amountIn) <= 0n) {
        return reply.code(400).send({ error: 'Invalid amount' })
    }

    const whitelist = getWhitelist(chainId)
    if (!whitelist) {
        return reply.code(400).send({ error: 'Chain not supported' })
    }

    if (whitelist.tokens.length > 0 &&
        !whitelist.tokens.some(t => t.toLowerCase() === tokenIn.toLowerCase()) &&
        !whitelist.tokens.some(t => t.toLowerCase() === tokenOut.toLowerCase())) {
        return reply.code(400).send({ error: 'Token not whitelisted' })
    }

    const quotePromises = whitelist.quoters.map(async (quoterUrl) => {
        try {
            const response = await fetch(`${quoterUrl}/quote`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify(request.body)
            })
            if (!response.ok) return null
            return await response.json() as QuoteResponse
        } catch {
            return null
        }
    })

    const quotes = (await Promise.all(quotePromises)).filter(q => q !== null)

    // Validate orders on-chain using the RFQ contract
    const validQuotes = []
    for (const quote of quotes) {
        const validation = await validateOrderOnChain(
            quote.order,
            quote.signature,
            taker,
            chainId
        )
        if (validation.valid) {
            validQuotes.push({
                ...quote,
                remaining: validation.remaining?.toString()
            })
        }
    }

    return { quotes: validQuotes }
})

server.listen({ port: 8080 }, (err, address) => {
    if (err) {
        console.error(err)
        process.exit(1)
    }
    console.log(`Server listening at ${address}`)
})