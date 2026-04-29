# `.claude/plans/`

Design / refactor plans tracked in-repo so future Claude sessions (and humans) can pick up where we left off.

## Current plans

- **`manual-exercise.md`** — strip oracles entirely from the protocol; replace post-expiry settlement with an 8-hour exercise window. This branch (`manual-exercise`) implements that.
- **`exercise-for-gas.md`** — gas-cost test plan for `exerciseFor` batching. Already implemented on the `auto-settlements` branch as `foundry/test/ExerciseForGas.t.sol`; numbers in `audit/results-exercise-for-gas.md` over there.

## Conventions

- One file per plan; markdown with a "Context" section up top.
- Settled decisions (window default, narrow/wide, etc.) stay in the plan file under "Settled decisions" — don't delete the rationale, just record what was chosen.
- When a plan ships to main, leave it here as a historical record (or delete if it's no longer informative).

## Branch context

- `main` — production
- `auto-settlements` — oracle-settled flavor with cash settlement, swapper, `claim` overloads, gas tests
- `manual-exercise` — this branch; no oracle, exercise-window only
