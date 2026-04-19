---
title: Oracles
sidebar_position: 5
---

# Oracles

An oracle is any contract implementing `IPriceOracle`:

```solidity
interface IPriceOracle {
    function expiration() external view returns (uint256);
    function isSettled() external view returns (bool);
    function settle(bytes calldata hint) external returns (uint256);
    function price() external view returns (uint256);
}
```

- `expiration()` — the timestamp this oracle settles against. Must match the option's expiration.
- `settle(hint)` — idempotent latch. First call post-expiry stores the settlement price; subsequent calls are no-ops.
- `price()` — reverts before `settle`, returns the latched price after.

Output is 18-decimal fixed-point, **consideration per collateral**. Same convention as strike.

## Per-option, pinned to expiry

Each option gets its own oracle instance. The factory deploys the appropriate wrapper at creation time, bound to the option's expiration timestamp. This means:

- Two options with different expiries have independent oracles, even if they point at the same underlying pool/feed.
- The oracle's `expiration()` is immutable — you can't accidentally settle against a different time.

## Supported sources

### Uniswap v3 TWAP (shipping today)

The factory accepts a Uniswap v3 pool address as `oracleSource`. It deploys a `UniV3Oracle` wrapper that, on `settle()`, reads the pool's observation buffer over a configurable window ending at expiry:

```solidity
CreateParams({
    collateral: address(weth),
    consideration: address(usdc),
    expirationDate: exp,
    strike: 3000e18,
    isPut: false,
    isEuro: false,         // or true
    oracleSource: address(wethUsdcPool),
    twapWindow: 1800       // 30-minute TWAP
});
```

Semi-strict timing: `settle()` works any time after expiry, as long as the observations covering `[expiration - twapWindow, expiration]` are still in the pool's ring buffer. For high-traffic pools this is days; for quieter ones it can be much shorter — be careful with long settlement delays.

Call `settle("")` with empty hint; Uniswap doesn't need any external input.

### Pre-deployed IPriceOracle

You can also pass any pre-deployed `IPriceOracle` directly as `oracleSource`. The factory detects this via the `expiration()` match and uses the contract as-is. This is how the unit tests work, and it enables:

- Oracle reuse across multiple options with the same expiry (deploy once, attach to many).
- Custom oracle implementations without factory changes.

### Chainlink (planned)

Chainlink's round-based model is a natural fit: take a `roundId` hint, verify it was the earliest round after expiry, latch that answer. No buffer-lifetime concerns.

Design sketch lives in `~/.claude/plans/chainlink-oracle.md`; it plugs into the same factory detection path as an additional `else if`.

## Permissionless settlement

`oracle.settle(hint)` has no access control. Any EOA or contract can pay the gas to latch the price. This is by design — settlement should never be held up waiting for a specific party.

In practice:
- Bots will settle high-value options automatically after expiry.
- Option holders can self-serve via `option.settle(hint)` if no one has settled yet (convenience forwarder).

## Caveats

- Oracle must be pre-verified at creation — the factory checks `expiration()` matches, but doesn't inspect the oracle's implementation. Use oracles you trust.
- Settlement price is one number. For options that need volatility or path-dependent settlement, this model doesn't fit.
- If the oracle reverts on `settle()` (e.g. Uniswap observations rolled off, Chainlink feed paused), the option can't be settled. Users can still pair-redeem pre-expiry to avoid this risk.
