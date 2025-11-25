Instructions for RFQ

- The RFQ Server receives a request from the front end for a price for the following:
- The requester wants to either swap Cash for an Option or reverse.
- Which direction doesn't matter because the price will contain a bid and ask price.
- I'm still trying to decide if it should be tokenIn/Out or Cash/Option, convince me which way. this will never be non options
- We will be using packages/foundry/RFQ.sol as a template but we don't necessarily need to hold to that exactly. 
- do not overengineer. only start with basics. here they are
- check the parameters from the request and make sure they are ok and everything is whitelisted according to the chain we're on (chainId)
- for now, create a hardcode list of addresses (for now localhost) to ping to get those quotes.
- the quotes will be EIP712 along with regular format for the server and client to parse 
- the server will call a function (that doesn't exist yet) that validates the EIP712 transaction is valid
- you will create a quoter service that is used only for testing purposes for now
- this quoter (in fastify) will perform the 712 txn creation. if you need a key, let me know and i'll create a test one or
- if you know how to create one, go for it and make the phrase simple and save it
- the reason i want you to stay lean is because i'm assuming i'm making changes, and adding layers
- very few comments please, and no md files with instructions
- dont add instructions for the client front end yet

---

## IMPLEMENTATION PLAN

### Architecture
- **tokenIn/tokenOut** (RECOMMENDED): Matches RFQ.sol exactly, more flexible, no assumptions about asset types, direction handled by makerSellsIn boolean
- Two services: qserver (aggregator) + quoter (test market maker)
- Shared types matching RFQ.sol Order structure

### 1. Core Types (types.ts)
- Order interface (from RFQ.sol)
- QuoteRequest interface (frontend → qserver)
- QuoteResponse interface (quoter → qserver)
- Whitelist config by chainId

### 2. EIP712 Utils (eip712.ts)
- DOMAIN_SEPARATOR builder
- ORDER_TYPEHASH constant
- signOrder(order, privateKey) → signature
- validateOrder(order, signature) → boolean

### 3. Config (config.ts)
- Hardcoded quoter addresses per chainId
- Token whitelist per chainId
- Test private key for quoter

### 4. Main Server (qserver/index.ts)
- POST /rfq endpoint
  - Validate request params (addresses, amounts, chainId)
  - Check whitelist
  - Ping all quoters in parallel
  - Validate EIP712 signatures
  - Return aggregated quotes

### 5. Test Quoter (quotes/index.ts)
- Separate fastify server (port 8081)
- POST /quote endpoint
  - Receive quote request
  - Calculate bid/ask prices (simple mock logic)
  - Sign Order with EIP712
  - Return signed quote + raw Order

### Files to Create/Modify
- types.ts (new)
- eip712.ts (new)
- config.ts (new)
- index.ts (modify - main server)
- quotes/index.ts (new - test quoter)
- package.json (add ethers for signing)

### Dependencies to Add
- viem (for EIP712 signing/validation)

### Test Flow
1. Start qserver (port 8080)
2. Start quoter (port 8081)
3. POST to qserver /rfq → returns signed quotes from quoter
4. Validate signatures work
