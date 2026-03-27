## Why
- Large Lua table constructions (e.g., `constructs.lua`) take several minutes, indicating a performance regression versus the previous map-backed implementation.
- Benchmarks (`tool/table_construct_bench.dart`) show nested numeric writes and vararg constructors costing 80–100 seconds per run, blocking gc.lua and sort.lua progress.
- We need defined guardrails for optimizing table allocation and iteration in the hybrid `TableStorage`.

## What Changes
- Introduce requirements for efficient dense table construction, sequential lookups, and vararg expansions within the interpreter.
- Ensure benchmarking coverage exists to quantify improvements and prevent regressions.

## Impact
- Enables follow-up implementation work to deliver measurable speedups for Lua table hotspots.
- Establishes spec and tasks for hybrid table storage behavior so future regressions can be detected.
