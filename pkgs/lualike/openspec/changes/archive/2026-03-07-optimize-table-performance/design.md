## Overview
We will optimize Lua table performance by improving the hybrid `TableStorage` structure and its integration with the interpreter’s table constructors.

## Key Decisions
- **Dense array growth**: switch from `List.length` assignments to amortized `add`/chunk growth for sequential numeric writes, keeping `_arrayCount` accurate while avoiding O(n²) resize costs.
- **Constructor pre-sizing**: estimate contiguous numeric span during AST evaluation and preallocate array capacity before inserting elements, minimizing repeated reallocations.
- **Vararg batching**: write unpacked values into contiguous buffers before transferring to the table to reduce repeated lookup and metamethod cost.

## Trade-offs
- Added logic increases code complexity; mitigated by unit tests and microbenchmarks.
- Pre-sizing relies on heuristics; fall back to hash map when density thresholds are unclear.

## Open Questions
- How to expose benchmark assertions in CI without prolonging runtime?
- Do weak tables or metamethod overrides require opt-out mechanisms for pre-sizing?
