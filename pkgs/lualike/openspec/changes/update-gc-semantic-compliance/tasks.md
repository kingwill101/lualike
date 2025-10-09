# GC Semantic Compliance — Actionable TODOs

This checklist consolidates recommendations from `gc_research.txt` into concrete work items. Track progress here and keep in sync with implementation.

## 0. Immediate Stabilization (Done/Next)
- [x] Detect weak mode via registered metatable across wrappers (Value.tableWeakMode fallback)
- [x] Delegate raw `Map` roots to their `Value` owner in GC discovery
- [x] Ensure ephemeron tables are tracked by scanning generations post-mark
- [x] Add focused logging for ephemeron tracking and weak-clearing
- [x] Add regression test: metatable visibility across wrappers (`test/gc/metatable_registry_test.dart`)
- [ ] Add regression test: weak-keys `pairs()` yields only strong keys after `collect` (unskip `test/gc/weak_keys_pairs_test.dart` once stable)

## 1. Credits & Weights (Allocation Units)
- [x] Centralize weights in `GcWeights` and track via `MemoryCredits`
- [x] Hook constructors/free and table mutations to adjust credits
- [x] Replace bytes thresholds with credits for minor/major triggers
- [ ] Add diagnostics: `gc.totalCredits`, `youngCredits`, `oldCredits`, object histogram
- [ ] Document tuning workflow and defaults

## 2. Seven-State Aging (Lua 5.4)
- [ ] Introduce GC state enum: new → survival → old-0 → old-1 → old, touched-1/2
- [ ] Advance survivors across minor cycles (no direct young→old)
- [ ] Maintain touched lists to avoid “scan all old as roots”
- [ ] Tests: old→new links don’t get lost; touched old scanned in next minor

## 3. Write Barriers (Forward/Back)
- [ ] Centralize mutation helpers (table set, metatable set, upvalue attach)
- [ ] Forward barrier: old host stores young value ⇒ promote to at least old-0
- [ ] Back barrier: old host mutated ⇒ mark touched-1
- [ ] Remove “treat all old as roots” minor fallback
- [ ] Tests: barrier behavior on all mutation sites

## 4. Finalizers (__gc)
- [ ] Mark for finalization only if `__gc` existed at metatable set time
- [ ] Execute synchronously, reverse registration order, no yields
- [ ] Re-mark before finalizers to handle resurrection; collect later cycles
- [ ] Prevent nested GC during finalizers; convert errors to warnings
- [ ] Tests: ordering, resurrection, non-yielding enforcement

## 5. Weak Tables & Ephemerons
- [x] Weak-mode detection from registered metatable across wrappers
- [x] Add owner delegation for raw `Map` roots
- [x] Post-mark scan to ensure ephemeronTables populated
- [ ] Remove arbitrary iteration limit in `_convergeEphemerons` (true fixed-point)
- [ ] Apply `__mode` changes on next cycle (dynamic weakness)
- [ ] Respect resurrected timing: clear weak-values before finalizers; weak-keys after
- [ ] Tests: `k`, `v`, `kv` modes; resurrection timing; dynamic `__mode` change

## 6. API & Diagnostics
- [ ] Expand `collectgarbage` API for tuning (minor/major multipliers, pause, mode)
- [ ] Mode switching: incremental vs generational at runtime
- [ ] Introspection: recent cycle times, weak-table stats, per-state counts
- [ ] Docs: `docs/cli.md` and user-facing GC docs

## 7. Stack vs Heap Correctness
- [x] Build comprehensive root set (env, call/eval stacks, coroutines)
- [ ] Audit interpreter frames to ensure no direct heap ownership on stack
- [ ] Tests: locals/globals/lambdas stay alive only via roots

## 8. Performance & Safety Valves
- [ ] Incremental major stepper tied to credits (work debt)
- [ ] Adaptive aggressiveness if cycles lag behind
- [ ] Benchmarks: large graphs, steady-state churn

## 9. Integration & Regressions
- [ ] Unskip `test/gc/weak_keys_pairs_test.dart`; add more coverage mirroring `gc.lua`
- [ ] Create minimal repros for each gc.lua subsection (weak, finalizers, ephemerons)
- [ ] Run `./test_runner --test=gc.lua --debug` regularly and compare to Lua CLI

## 10. Documentation & Changelog
- [ ] Update `docs/` with GC semantics and tuning guide
- [ ] Annotate code with non-obvious decisions, especially barriers/aging
- [ ] Add CHANGELOG entries for each capability

