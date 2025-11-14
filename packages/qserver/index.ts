import fastify from 'fastify'
import { isAddress } from 'viem'
import type { QuoteRequest, QuoteResponse } from './types'
import { getWhitelist, RFQ_CONTRACT } from './config'
import { validateSignature } from './eip712'

const server = fastify()

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

    const validQuotes = []
    for (const quote of quotes) {
        const isValid = await validateSignature(
            quote.order,
            quote.signature,
            chainId,
            RFQ_CONTRACT
        )
        if (isValid) {
            validQuotes.push(quote)
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