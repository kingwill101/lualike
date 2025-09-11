## Lualike GC: Current State vs Lua 5.4 C Collector

This document analyzes the current garbage collection (GC) implementation in lualike and contrasts it with the reference Lua 5.4 collector (see `gc/lgc.c` and `gc/lgc.h`). It identifies correctness and completeness gaps, with a focus on weak tables, traversal accuracy, finalization, and generational behavior.

### 1) Overview of Current Implementation

- Core types
  - `GCObject` (`lib/src/gc/gc.dart`): base with `marked: bool`, `isOld: bool`, `getReferences(): List<Object?>`, `free()`.
  - `GenerationalGCManager` (`lib/src/gc/generational_gc.dart`): holds `youngGen`/`oldGen` lists, does simple mark/sweep; minor = mark young with old as roots; major = mark both and call finalizers.
  - Registered objects: `Value`, `Environment`, `Box`, `Coroutine` register with GC (see `value.dart`, `environment.dart`, `coroutine.dart`).

- Mark algorithm (simplified)
  - `_discover(Object? obj)` marks `GCObject` and traverses `getReferences()`; also recurses into `Environment`, generic `Map`, and `Iterable` by structural walk.
  - No color states (only `marked` boolean), no gray lists, no incremental states.

- Sweep/finalization
  - Major: `_separate` keeps marked, collects unmarked; if a `Value` has `__gc`, it is “resurrected” once via `_toBeFinalized`, then `_callFinalizersAsync()` invokes `__gc` and moves it to `_alreadyFinalized`.
  - Minor: frees unmarked from young gen without finalizer handling.

- Generational approximation
  - No barriers; minor collections conservatively add all old-gen objects to the root set.
  - `estimateMemoryUse()` is object-count-based, not bytes.

### 2) Key Architectural Gaps vs Lua 5.4

1. Table traversal accuracy (critical)
   - In `Value.getReferences()`, tables (when `raw is Map`) are NOT exposed to the GC; only `metatable` is returned. Traversal of the table entries currently relies on `_discover` seeing a raw `Map` object. Because `_discover` starts from `Value` instances and `getReferences()` does not include `raw`, the table contents may never be visited. This risks unmarking objects reachable only through tables.
   - Consequence: correctness bug and basis for weak table support is missing (GC cannot reason about keys/values if it cannot see them).

2. Weak table semantics (missing)
   - Lua relies on `__mode` metatable string to configure weak values (`v`), weak keys (`k`), or both (`kv`).
   - The C collector classifies tables into `weak`, `allweak`, `ephemeron` lists and implements: not marking through weak values; ephemeron (weak-keys) convergence; and clearing of dead keys/values (see `lgc.c: traverseweakvalue`, `traverseephemeron`, `convergeephemerons`, `clearbykeys/clearbyvalues`).
   - Current lualike: only test helpers detect `__mode` in `lib/src/stdlib/lib_test.dart`; GC ignores it. Weak keys/values are not honored; entries are never cleared.

3. Barriers and aging (missing)
   - Lua’s invariants (black cannot point to white) and generational aging (`G_NEW`, `G_SURVIVAL`, `G_OLD*`, `G_TOUCHED*`) with forward/back barriers are absent. Our minor collection workaround (treat old gen as roots) avoids missing old→young edges but over-retains and limits performance.

4. Root set policy (underspecified)
   - Lua marks: main thread, registry, global metatables, threads, open upvalues, etc. (see `restartcollection`, `remarkupvals`).
   - Our roots are provided ad hoc by call sites; minor adds entire old gen. We do not have an explicit canonical root-set generator for interpreter state: global env, call stack frames, coroutines, `_G`, loaded modules, etc.

5. Finalization/resurrection (partially implemented)
   - We approximate the two-phase finalization: separate finalizable unreachables, run `__gc`, “resurrect” for one cycle. We do not re-mark after resurrection like the C collector’s `markbeingfnz` + propagate + converge sequences do during `atomic`.
   - Current approach passes existing tests but is semantically looser around complex resurrection graphs.

6. Upvalues and closures (tracking clarity)
   - `Value` can hold `upvalues: List<Upvalue>?` and `functionBody`, but `Value.getReferences()` does not include them. `Upvalue` is not a `GCObject`. This means upvalues are retained by Dart references, not by GC graph semantics, and will not be freed by our collector. This is acceptable if they are cheap and scoped by function lifetimes, but it diverges from Lua’s model where upvalues are collectible objects.

7. Non-GC objects traversal and performance
   - `_discover` traverses any `Map`/`Iterable` recursively, visiting primitives that are not `GCObject`. While safe, it is noisy and may become costly. A filter to only descend when entries are `GCObject` (or containers that likely contain `GCObject`) would reduce overhead.

8. Memory accounting
   - We trigger collections using object counts, not approximate bytes. Lua tunes thresholds using bytes and multiple parameters (`PAUSE`, `STEPSIZE`, etc.). Our tuning knobs (`minorMultiplier`, `majorMultiplier`) are coarse.

### 3) Weak Tables: Required Semantics

From the C collector:
- `__mode = 'v'` (weak values): do not mark through values; in atomic/clear phases, remove entries whose values are dead.
- `__mode = 'k'` (weak keys): ephemeron behavior. A value is kept alive only if its key is kept alive by something else. Requires convergence loop (see `convergeephemerons`). Keys not strongly reachable are cleared.
- `__mode = 'kv'` (all-weak): do not traverse either; keys/values are both weak, with appropriate clearing.

To support this, GC must:
1) Be able to identify that a `Value`-table is weak and in what way (via its `metatable['__mode']`).
2) Traverse tables differently based on mode.
3) Maintain per-collection temporary lists of weak/allweak/ephemeron tables to clear or converge.
4) Perform a final clear of keys/values after marking and finalizer separation.

### 4) Concrete Findings in Code

- `lib/src/value.dart`
  - Does not expose `raw` (the table) via `getReferences()`. It also does not expose `upvalues`/`functionBody` for marking.
  - `metatable` is a plain `Map<String, dynamic>`, entries are often `Value` or `Function`, so GC can see it via `_discover(Map)` but not influence weak policy because the `Map` is not the table’s storage; the owner `Value` holds the policy.

- `lib/src/environment.dart`
  - `Box<T>` extends `GCObject` and is registered; `getReferences()` returns the boxed value if it is a `GCObject`. Boxes are tracked as heap cells. Good.
  - `Environment.getReferences()` traverses parent and values’ boxed values. Good.

- `lib/src/gc/generational_gc.dart`
  - No concept of weak lists, ephemeron convergence, or barriers.
  - `_discover` has special cases for `Environment`, `Map`, and `Iterable`, but not for `Value` being a table; relies on eventually seeing the `Map` independently, which does not happen.
  - Finalizers are run after separation; no re-mark phase post-resurrection.

- `gc/lgc.c`/`gc/lgc.h`
  - Full implementation of: colors, aging, barriers, ephemeron/weak traversal, convergence, separation of finalizables, atomic-phase ordering, and clearing.

### 5) Risks and Impact

- Functional correctness risk
  - Table-contained objects may be unmarked and collectible once GC runs, if not additionally rooted elsewhere.
  - Weak table semantics are currently incorrect (not weak), which can cause memory leaks (should be cleared) and behavioral differences from Lua.

- Stability risk
  - Introducing weak semantics without fixing traversal can make objects disappear unexpectedly.

- Performance risk
  - Traversing all `Map`/`Iterable` entries regardless of content type is inefficient.

### 6) Summary of Gaps to Close

1) Fix table traversal by making GC aware of `Value` tables and their `__mode`.
2) Implement weak-values traversal and ephemeron (weak-keys) convergence and post-mark clearing.
3) Introduce a canonical root set generator from interpreter state.
4) Add a minimal, non-intrusive write-barrier strategy or keep “old as roots” as an interim.
5) Tighten finalization to better match resurrection semantics (optional step-wise improvement).
6) Consider marking upvalues/functions if we want them to be collectible (or document the choice).
7) Improve memory accounting heuristics.

### 7) About Dart WeakReference/Finalizer

- `Finalizer`/`WeakReference` operate with the Dart VM GC, not our logical GC. Because we keep strong references to all `GCObject`s in the manager’s generation lists, Dart GC will not collect them until we remove them.
- Use cases where they do help:
  - Host interop objects (e.g., file handles, DOM nodes) that should clean up when the hosting Dart object dies irrespective of lualike GC cycles.
  - Supplementary safety net for external resources in release builds.
- Use cases where they should not be used:
  - Implementing Lua weak table semantics or core reachability; that must be driven by our own GC marks.


