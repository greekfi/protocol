import { keccak256, encodePacked, encodeAbiParameters, parseAbiParameters, recoverAddress } from 'viem'
import type { Order } from './types'

export const ORDER_TYPEHASH = keccak256(
  encodePacked(
    ['string'],
    ['Order(address maker,address tokenIn,address tokenOut,uint256 price1e18,uint256 maxIn,uint256 minPerFillIn,uint256 maxPerFillIn,uint256 deadline,uint256 nonce,bool makerSellsIn,address allowedFiller,uint256 feeBps)']
  )
)

export function getDomainSeparator(chainId: number, verifyingContract: string) {
  const domainTypeHash = keccak256(
    encodePacked(
      ['string'],
      ['EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)']
    )
  )
  
  return keccak256(
    encodeAbiParameters(
      parseAbiParameters('bytes32, bytes32, bytes32, uint256, address'),
      [
        domainTypeHash,
        keccak256(encodePacked(['string'], ['PriceIntent'])),
        keccak256(encodePacked(['string'], ['1'])),
        BigInt(chainId),
        verifyingContract as `0x${string}`
      ]
    )
  )
}

export function hashOrder(order: Order) {
  return keccak256(
    encodeAbiParameters(
      parseAbiParameters('bytes32, address, address, address, uint256, uint256, uint256, uint256, uint256, uint256, bool, address, uint256'),
      [
        ORDER_TYPEHASH,
        order.maker as `0x${string}`,
        order.tokenIn as `0x${string}`,
        order.tokenOut as `0x${string}`,
        order.price1e18,
        order.maxIn,
        order.minPerFillIn,
        order.maxPerFillIn,
        order.deadline,
        order.nonce,
        order.makerSellsIn,
        order.allowedFiller as `0x${string}`,
        order.feeBps
      ]
    )
  )
}

export function getOrderDigest(order: Order, chainId: number, verifyingContract: string) {
  const domainSeparator = getDomainSeparator(chainId, verifyingContract)
  const orderHash = hashOrder(order)
  
  return keccak256(
    encodePacked(
      ['string', 'bytes32', 'bytes32'],
      ['\x19\x01', domainSeparator, orderHash]
    )
  )
}

export async function validateSignature(
  order: Order,
  signature: string,
  chainId: number,
  verifyingContract: string
): Promise<boolean> {
  try {
    const digest = getOrderDigest(order, chainId, verifyingContract)
    const recoveredAddress = await recoverAddress({
      hash: digest,
      signature: signature as `0x${string}`
    })
    
    return recoveredAddress.toLowerCase() === order.maker.toLowerCase()
  } catch {
    return false
  }
}
