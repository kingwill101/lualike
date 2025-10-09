## Why
Lua’s GC semantics (generational aging, barriers, weak tables/ephemerons, and finalizers) must match Lua 5.4 behavior for correctness and to pass the reference `gc.lua` suite. Our current implementation diverges in several areas (weak-key discovery, ephemeron convergence, finalizer ordering, write barriers, and credit-based scheduling).

## What Changes
- Strengthen weak table semantics (ephemerons): ensure detection across wrappers, converge correctly, and clear keys/values at the right phase.
- Introduce robust write barriers and multi-state aging consistent with Lua 5.4.
- Make finalizer execution synchronous and ordered (reverse registration), with no yielding and correct resurrection handling.
- Use “credits” (allocation units) for scheduling triggers instead of bytes, with diagnostics.
- Expose GC tuning and mode selection via `collectgarbage`-compatible APIs.
- Improve stack vs heap separation and root set coverage.

## Impact
- Affected specs: garbage-collection (weak tables, ephemerons, finalizers, scheduling), lua-compatibility.
- Affected code: `lib/src/gc/*`, `lib/src/value.dart`, `lib/src/stdlib/lib_base.dart`, `lib/src/environment.dart`, `lib/src/interpreter/*`.
- Tests: expand GC unit tests and add regression tests for weak tables and finalizers. Validate with `luascripts/test/gc.lua`.

