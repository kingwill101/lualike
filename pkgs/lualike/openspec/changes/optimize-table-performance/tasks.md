## 1. Investigation & Baselines
- [ ] 1.1 Confirm current TableStorage hot spots using `tool/table_construct_bench.dart` and record results.
- [ ] 1.2 Document existing interpreter paths that build large tables (constructor, vararg unpack, reverse assignment loops).

## 2. Spec & Design
- [ ] 2.1 Draft design detailing dense-array growth strategy, hash fallbacks, and table constructor pre-sizing.
- [ ] 2.2 Validate design against Lua semantics (weak tables, metamethod interactions).

## 3. Implementation
- [ ] 3.1 Optimize TableStorage dense writes (append vs resize) and ensure `_arrayCount` correctness.
- [ ] 3.2 Add pre-sizing or batching logic for interpreter table constructors and vararg unpack.
- [ ] 3.3 Ensure sparse numeric keys remain on hash path without regressions.
- [ ] 3.4 Implement direct dense-set fast path for interpreter assignment (bypass generic `_setRawTableEntry` when possible).
- [ ] 3.5 Batch GC credit updates / MemoryCredits recalcs during dense writes to avoid per-slot overhead.
- [ ] 3.6 Optimize `table.unpack` expansion (bulk copy / wrapper reuse) to reduce per-element creation.

## 4. Validation
- [ ] 4.1 Extend microbenchmarks to cover literal, reverse assignment, and vararg scenarios; log before/after metrics.
- [ ] 4.2 Run `./test_runner -v --test=constructs.lua` and `--test=sort.lua` to confirm end-to-end improvements.
- [ ] 4.3 Update/ add unit tests for TableStorage edge cases (sparse keys, append, removal).

## 5. Documentation & Cleanup
- [ ] 5.1 Document performance expectations and benchmarking workflow in `docs/` or project README.
- [ ] 5.2 Remove temporary diagnostics and ensure `dart format` passes.
