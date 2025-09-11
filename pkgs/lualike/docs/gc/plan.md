## Lualike GC: Phased Implementation Plan

A pragmatic sequence to reach Lua-compatible weak semantics and safer GC without introducing excessive complexity up front.

### Phase 0: Baseline and Guardrails

- Add docs and comments to clarify current limitations (done via analysis/recommendations docs).
- Ensure a single entry point for major GC with clear phases to enable future weak handling.

Deliverables:
- No code changes beyond scaffolding methods if needed.

### Phase 1: Correct Table Reachability

- Changes:
  - Update `Value.getReferences()` to include table contents for strong traversal.
    - Only add entries (keys/values) that are `GCObject` or `Value` containing `GCObject` recursively.
    - Keep metatable included when it contains `GCObject` references.
  - Add an internal helper such as `Value.tableWeakMode` and `Value.tableEntriesForGC()`.
  - Add `GenerationalGCManager.buildRootSet(vm)` and use it in `majorCollection()`.

- Tests:
  - New tests ensuring values reachable only via a table are kept alive.
  - No changes to minor behavior.

### Phase 2: Weak Values (`__mode='v'`)

- Major collection only:
  - During mark, for weak-values tables, traverse keys (strong) and record table in `weakValuesTables`.
  - After mark and finalizable separation/re-mark, clear entries whose values are dead.

- Tests:
  - Table keeps keys but removes entries where value was unmarked after GC.
  - Ensure no clearing occurs during minor GC.

### Phase 3: Weak Keys / Ephemeron (`__mode='k'`)

- Major collection only:
  - During initial traversal, add ephemeron tables to `ephemeronTables` and do not mark values by default.
  - After normal propagation, run convergence loop: if a key becomes black via other paths, mark its value and continue until fixed point (mirrors Lua's `convergeephemerons`).
  - Finally clear entries with dead keys.

- Tests:
  - Value survives only when its key is strongly reachable through non-table paths.
  - Convergence cases (chains of ephemerons in one or multiple tables).

### Phase 4: All-Weak (`__mode='kv'`)

- Major collection only:
  - Do not traverse entries; add tables to `allWeakTables` for clearing after marking.
  - Clear both dead keys and values.

- Tests:
  - Entries disappear when neither key nor value is strongly reachable.

### Phase 5: Finalization Tightening

- After separating finalizables in major GC:
  - Mark and propagate from `_toBeFinalized` objects before weak clearing.
  - Keep `_alreadyFinalized` to prevent re-running `__gc`.

- Tests:
  - `__gc` runs once.
  - Objects reachable only via finalizers survive the current cycle and may be collected in the next.

### Phase 6: Performance and Heuristics

- Optional improvements:
  - Filter traversal of `Map`/`Iterable` when no `GCObject` entries exist.
  - Improve `estimateMemoryUse()` with rough size estimates.

- Out-of-scope for initial parity: full color states, write barriers, true incremental scheduler.

### Phase 7: Upvalues/Closures (Optional)

- Option A (default): Document current approach (not GC objects), defer changes.
- Option B: Make `Upvalue` a `GCObject`, wire `Value.getReferences()` to include upvalues and `functionBody`.

### Testing and Tooling

- Add targeted Dart tests under `test/gc/`:
  - `weak_values_test.dart`
  - `weak_keys_ephemeron_test.dart`
  - `weak_all_test.dart`
  - `finalization_resurrection_test.dart`
  - `table_traversal_reachability_test.dart`

- Use `LOGGING_ENABLED=true` during tests to aid debugging.
- Add minimal Lua scripts under `luascripts/test/` if needed to mirror Lua behavior and compare with reference interpreter.

### Rollout Strategy

- Implement and land phases 1 → 4 with tests per phase; run full test suite after each phase.
- Phase 5 optional in first pass if tests are green, but recommended for parity.
- Phases 6–7 are optimization and optional parity extensions.


