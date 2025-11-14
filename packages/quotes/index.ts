import fastify from 'fastify'
import { privateKeyToAccount } from 'viem/accounts'
import { keccak256, encodePacked, encodeAbiParameters, parseAbiParameters } from 'viem'

interface QuoteRequest {
  chainId: number
  tokenIn: string
  tokenOut: string
  amountIn: string
  taker: string
}

interface Order {
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

const PRIVATE_KEY = '0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80'
const RFQ_CONTRACT = '0x0000000000000000000000000000000000000000'
const account = privateKeyToAccount(PRIVATE_KEY as `0x${string}`)

const ORDER_TYPEHASH = keccak256(
  encodePacked(
    ['string'],
    ['Order(address maker,address tokenIn,address tokenOut,uint256 price1e18,uint256 maxIn,uint256 minPerFillIn,uint256 maxPerFillIn,uint256 deadline,uint256 nonce,bool makerSellsIn,address allowedFiller,uint256 feeBps)']
  )
)

function getDomainSeparator(chainId: number, verifyingContract: string) {
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

function hashOrder(order: Order) {
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

function getOrderDigest(order: Order, chainId: number, verifyingContract: string) {
  const domainSeparator = getDomainSeparator(chainId, verifyingContract)
  const orderHash = hashOrder(order)
  
  return keccak256(
    encodePacked(
      ['string', 'bytes32', 'bytes32'],
      ['\x19\x01', domainSeparator, orderHash]
    )
  )
}

const server = fastify()

server.post<{ Body: QuoteRequest }>('/quote', async (request, reply) => {
  const { chainId, tokenIn, tokenOut, amountIn, taker } = request.body

  const price1e18 = 1000000000000000000n
  const deadline = BigInt(Math.floor(Date.now() / 1000) + 3600)
  const nonce = BigInt(Math.floor(Math.random() * 1000000))

  const order: Order = {
    maker: account.address,
    tokenIn,
    tokenOut,
    price1e18,
    maxIn: BigInt(amountIn),
    minPerFillIn: 0n,
    maxPerFillIn: 0n,
    deadline,
    nonce,
    makerSellsIn: true,
    allowedFiller: taker,
    feeBps: 0n
  }

  const digest = getOrderDigest(order, chainId, RFQ_CONTRACT)
  const signature = await account.signMessage({
    message: { raw: digest }
  })

    reply
        .code(200)
        .header('Content-Type', 'application/json; charset=utf-8')
        .send({
            order,
            signature
        })
  return
})

server.listen({ port: 8081 }, (err, address) => {
  if (err) {
    console.error(err)
    process.exit(1)
  }
  console.log(`Quoter listening at ${address}`)
})
