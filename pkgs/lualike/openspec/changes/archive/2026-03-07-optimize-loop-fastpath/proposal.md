## Why
- Numeric `for` loops still spend most of their time rebuilding environments and boxing locals despite the TableStorage gains.
- `constructs.lua`/`sort.lua` continue to burn tens of seconds because each iteration re-enters the generic AST visitor and triggers full environment resets.
- We need a focused plan to add a fast path for simple numeric loops so hot paths no longer pay the generic interpreter overhead while keeping semantics intact.

## What Changes
- Detect simple numeric `for` loops (and the common `for`-in over numeric arrays) that are safe to specialize.
- Introduce a loop executor that reuses the existing loop environment and boxed counter without re-running the heavy reset logic.
- Guard the fast path so we fall back to the existing interpreter whenever the loop body needs full semantics (metamethods, locals, goto, etc.).
- Benchmark the new path against the existing `table_bench`/`constructs.lua` scenarios and document the target improvement.

## Impact
- Substantially lower per-iteration overhead for tight numeric loops, improving `constructs.lua`, `sort.lua`, and user scripts with large numeric loops.
- Requires careful guards to avoid changing observable semantics (metamethods, `goto`, `break`/`return`).
- Adds new test coverage for the specialized loop behaviour and fallback scenarios.
