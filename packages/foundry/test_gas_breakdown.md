# Gas Breakdown for Option.mint(100e18)

## Call Stack:
```
Option.mint(uint256 amount)                     [public, notLocked]
  └─> Option.mint(address account, uint256 amount)    [public, notLocked, nonReentrant]
      └─> Option.mint_(address account, uint256 amount)    [internal, notExpired, validAmount]
          ├─> redemption.mint(account, amount)
          │   ├─> Modifiers: onlyOwner, notExpired, notLocked, nonReentrant, validAmount, validAddress
          │   ├─> collateral.balanceOf(this)                [CALL: 2,600 gas]
          │   ├─> _factory.transferFrom(...)                [CALL: ~52,000 gas]
          │   │   ├─> _redemptionsMap[msg.sender]           [SLOAD: 2,100 gas]
          │   │   └─> collateral.safeTransferFrom(...)      [CALL: ~50,000 gas]
          │   │       ├─> balanceOf(from)                    [SLOAD: 2,100 gas]
          │   │       ├─> allowance(from, factory)           [SLOAD: 2,100 gas]
          │   │       ├─> balances[from] -= amount           [SSTORE: 2,900 gas]
          │   │       ├─> balances[to] += amount             [SSTORE: 20,000 gas - COLD]
          │   │       ├─> allowance -= amount                [SSTORE: 2,900 gas]
          │   │       └─> Transfer event                     [LOG: ~1,500 gas]
          │   ├─> collateral.balanceOf(this)                [CALL: 600 gas - warm]
          │   ├─> fee calculation                           [~100 gas]
          │   ├─> _mint(account, amount - fee)              [~45,000 gas]
          │   │   ├─> balances[account] += amount           [SSTORE: 20,000 gas - COLD]
          │   │   ├─> totalSupply += amount                 [SSTORE: 2,900 gas]
          │   │   └─> Transfer event                        [LOG: ~1,500 gas]
          │   └─> fees += fee                               [SSTORE: 2,900 gas]
          └─> Option._mint(account, amount - fee)          [~45,000 gas]
              ├─> balances[account] += amount               [SSTORE: 2,900 gas - warm]
              ├─> totalSupply += amount                     [SSTORE: 2,900 gas]
              └─> Mint event                                [LOG: ~1,500 gas]
```

## Estimated Gas Breakdown:

### Option.mint() Entry (2 wrapper calls)
- notLocked modifier (2x):                        ~4,200 gas
- nonReentrant modifier:                          ~2,900 gas
- notExpired modifier:                            ~2,100 gas
- validAmount modifier:                           ~300 gas
**Subtotal:**                                     ~9,500 gas

### Redemption.mint() Call
- External call overhead:                         ~700 gas
- Modifiers (onlyOwner, notExpired, notLocked, nonReentrant, validAmount, validAddress): ~12,000 gas
- collateral.balanceOf(this) - before:            ~2,600 gas
- _factory.transferFrom():                        ~52,000 gas
  - Authorization check (_redemptionsMap):        ~2,100 gas
  - ERC20.safeTransferFrom():                     ~50,000 gas
    - balanceOf(from) SLOAD:                      ~2,100 gas
    - allowance SLOAD:                            ~2,100 gas
    - balances[from] SSTORE:                      ~2,900 gas
    - balances[redemption] SSTORE (cold):         ~20,000 gas
    - allowance SSTORE:                           ~2,900 gas
    - Transfer event:                             ~1,500 gas
    - SafeERC20 overhead:                         ~1,000 gas
- collateral.balanceOf(this) - after:             ~600 gas
- Fee calculation:                                ~100 gas
- Redemption._mint(account, amount - fee):        ~45,000 gas
  - balances[account] SSTORE (cold):              ~20,000 gas
  - totalSupply SSTORE:                           ~2,900 gas
  - Transfer event:                               ~1,500 gas
  - ERC20._update overhead:                       ~3,000 gas
  - _accounts tracking (_update):                 ~17,000 gas (push to array + mapping)
- fees SSTORE:                                    ~2,900 gas
**Subtotal:**                                     ~115,000 gas

### Option._mint() Call  
- balances[account] SSTORE (warm):                ~2,900 gas
- totalSupply SSTORE:                             ~2,900 gas
- Transfer event:                                 ~1,500 gas
- ERC20._update overhead:                         ~3,000 gas
**Subtotal:**                                     ~10,300 gas

### Miscellaneous
- Memory operations:                              ~2,000 gas
- Stack operations:                               ~1,000 gas
- Return data:                                    ~200 gas

**TOTAL ESTIMATED:**                              ~138,000 gas

## Actual Gas: ~229,000 gas

## Missing ~91,000 gas! Where is it?

Let me check what's in Redemption._update()...
