## Lualike GC: Recommendations and Prioritized Fixes

This document prescribes targeted changes to bring lualike’s GC closer to Lua 5.4 semantics, with emphasis on correctness first, then performance.

### Priorities

1) Correct table traversal and root set generation
2) Implement weak table semantics (values, keys/ephemeron, both)
3) Finalization tightening (resurrection-aware marking)
4) Minimal generational safety (barrier approximation or maintained conservative roots)
5) Optional: Upvalue/closure reachability modeling and memory heuristics

### 1) Correct Table Traversal

- Problem: `Value.getReferences()` does not expose table entries; GC depends on seeing raw `Map` elsewhere, which it does not from `Value` roots.
- Recommendation:
  - Change `Value.getReferences()` to include:
    - For table values: all referenced `Value` entries and keys that are `GCObject` (but conditionally, see weak handling below).
    - The `metatable` if it contains `GCObject` entries (already indirectly handled, but keep explicit for clarity).
    - Optionally, the function metadata (`upvalues`, `functionBody`) if we want them collectible (see Section 5).
  - Add a capability to report whether this table is weak and in what mode, so the GC can modulate traversal.

Implementation sketch:
- Add to `Value`:
  - `bool get isTable => _raw is Map;` (already exists)
  - `String? tableWeakMode` derived from `metatable['__mode']` when `isTable`.
  - A special `getReferencesForGC({required bool strongKeys, required bool strongValues})` used by GC only.

### 2) Weak Table Semantics

- Modes:
  - `__mode = 'v'`: weak values. Mark through keys, not through values. After mark, clear entries whose values are dead.
  - `__mode = 'k'`: weak keys (ephemeron). Requires convergence: a value becomes reachable only if its key becomes black via non-table roots; otherwise both can be collected. After convergence, clear entries with dead keys.
  - `__mode = 'kv'`: all-weak. Do not traverse entries; clear keys/values of dead ones after marking.

- Recommendations for our collector:
  - During major collection:
    1) Traverse strong tables normally.
    2) For weak-values tables, traverse only keys; add tables to a temporary `weakValuesTables` list for a later clear-by-values pass.
    3) For weak-keys (ephemeron) tables, traverse array part normally; for hash part, perform the ephemeron algorithm:
       - First pass: treat as if keys are not marked; add table to `ephemeronTables` list.
       - After normal propagation, perform convergence loop: while any table marks a new value due to a key turning black, propagate again until stable (mirrors `convergeephemerons`).
       - Then schedule clear-by-keys.
    4) For all-weak, add to `allWeakTables` and skip traversing keys/values.
    5) After separation of finalizables and re-mark of being-finalized, execute clear passes in order similar to `atomic` in Lua.
  - During minor collection: skip weak semantics (minor frees only young, no finalization), or conservatively treat all old-gen tables as strong to keep correctness until we add barriers. Simpler path: minor collection should not delete table entries; only major collection mutates weak tables.

Practical deviations accepted:
- We can ignore array vs hash partitioning and treat Dart `Map` uniformly. Correctness hinges on how we classify entries based on weak mode and whether key/value is a `GCObject`.

### 3) Finalization Tightening

- Current: `_toBeFinalized` resurrects, then `__gc` runs; we do not re-mark after resurrection.
- Recommendation (major only):
  - After separating finalizables, add a “re-mark” phase: mark objects in `_toBeFinalized` and propagate, so objects reachable from finalizers are considered alive for the next cycle (akin to `markbeingfnz` + propagate).
  - Keep `_alreadyFinalized` to prevent double finalization while allowing objects to be finally collected in subsequent cycles.

### 4) Generational Safety Without Full Barriers

- Keep current conservative approach for minor collections (treat all old as roots). It is slow but safe and avoids write-barrier complexity for now.
- Add a note in code that minor GC never mutates weak tables; only major GC applies weak clearing.

### 5) Upvalues and Functions

- Options:
  - A) Keep as today (not GC-tracked objects). Document that upvalues/AST nodes are owned by function values and lifetimes are tied to `Value` reachability. This is acceptable if memory footprint is small.
  - B) Make `Upvalue` implement `GCObject` and have `Value.getReferences()` include `upvalues` and `functionBody` when present. This aligns with Lua’s upvalue tracking and enables `__gc` on userdata captured by closures to be collected when closures die.

Recommendation: Start with A (documented), re-evaluate after functional parity with weak tables.

### 6) Root Set Definition

- Provide a single `List<Object?> buildRootSet(Interpreter vm)` function that returns:
  - Global/root `Environment`, current call stack frames, all live `Coroutine` objects, the `_G` table value, module cache table(s), any VM singletons that hold `GCObject`s.
  - Interpreter holds reference to `GenerationalGCManager`, but the GC should not be its own root.

### 7) Memory Accounting & Tuning

- Keep count-based trigger for now; add scaling factors to avoid thrashing.
- Future: estimate bytes by type (Value table entry count, Environment slot count, etc.). Not critical for correctness.

### 8) Dart Finalizer/WeakReference Usage

- Do not use for implementing Lua semantics.
- Consider exposing a facility for host-bound resources to register a Dart `Finalizer` if the embedding app wants OS-level cleanup independent of lualike GC. Keep separated from core GC.

### 9) API and Data-Structure Changes (Minimal)

- `Value`:
  - Add helpers: `bool get hasWeakValues`, `bool get hasWeakKeys`, `String? get weakMode`.
  - Add an internal method used by GC: `Iterable<MapEntry<dynamic, dynamic>> tableEntriesForGC()` to avoid exposing raw `Map` publicly.
  - Update `getReferences()` to include table references only when the GC asks for strong traversal (or provide a dedicated GC entry point to avoid mixing responsibilities).

- `GenerationalGCManager`:
  - Add fields per-cycle: `List<Value> weakValuesTables`, `List<Value> allWeakTables`, `List<Value> ephemeronTables` (or `Set`), cleared each major cycle.
  - Split major collection into phases: mark → separate → re-mark finalizables → converge ephemerons → clear weak by values/keys → finalize.
  - Provide a `collectMajor()` that internally builds roots via `buildRootSet(vm)`.

### 10) Testing Strategy

- Add focused tests for:
  - Weak values: values collected, keys preserved; entries removed after major GC.
  - Weak keys (ephemeron): require convergence; values live only if keys are strongly reachable.
  - All-weak: both sides can disappear; table becomes empty appropriately.
  - Finalization: `__gc` runs once, resurrection keeps objects one extra cycle.
  - Regression: no deletion during minor GC; only major applies weak clearing.


