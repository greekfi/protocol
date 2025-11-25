import { kv } from '@vercel/kv'
import type { QuoteResponse } from './types'

const TX_PREFIX = 'tx:'
const DEFAULT_TTL = 3600 // 1 hour

export async function saveTx(id: string, tx: QuoteResponse): Promise<void> {
  await kv.set(`${TX_PREFIX}${id}`, tx, { ex: DEFAULT_TTL })
}

export async function getTx(id: string): Promise<QuoteResponse | null> {
  return await kv.get(`${TX_PREFIX}${id}`)
}
