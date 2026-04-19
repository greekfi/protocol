# future/

Contracts and tests that aren't in the active critical path, parked here so
`foundry/` builds fast. Nothing here is compiled by default — `src = 'contracts'`
and `test = 'test'` in `foundry.toml` don't reach this directory.

## What's here

| Path | Purpose |
|------|---------|
| `contracts/OpHook.sol`         | Uniswap v4 hook — routes swaps to HookVault |
| `contracts/HookVault.sol`      | ERC4626 vault backing OpHook (auto-mint, Uniswap v3 cash↔collateral) |
| `contracts/OptionPricer.sol`   | On-chain pricing: Black-Scholes + v3 TWAP + smile + inventory |
| `contracts/BlackScholes.sol`   | Fixed-point BS math (int256 internal, WAD) |
| `contracts/ConstantsBase.sol`  | Uniswap v4 pool/router addresses on Base |
| `contracts/ConstantsMainnet.sol` | Uniswap v4 addresses on Mainnet |
| `contracts/ConstantsUnichain.sol` | Uniswap v4 addresses on Unichain |
| `test/OpHook.t.sol`            | Hook + vault integration tests (forked chains) |
| `test/SafeCallback.sol`        | Test helper for v4 callback pattern |
| `test/OptionPrice.t.sol`       | BlackScholes unit tests |
| `script/DeployUpgradeable.s.sol` | Factory + hook deploy with HookMiner |

## Why parked

- **Uniswap v4 isn't currently the primary trading path** — RFQ via Bebop is.
- `uniswap-hooks`, `v4-core`, `v4-periphery`, and `universal-router` combined
  are ~100MB of source that compiles slowly and adds little value for the core
  protocol build.

## Using it

Temporarily pull things back into the main build when working on the v4 hook:

```bash
# from foundry/
git mv future/contracts/OpHook.sol contracts/
# ... repeat for whatever you need ...
forge build
```

Or add a profile in `foundry.toml`:

```toml
[profile.future]
src = "future/contracts"
test = "future/test"
```

…then `FOUNDRY_PROFILE=future forge test`.
