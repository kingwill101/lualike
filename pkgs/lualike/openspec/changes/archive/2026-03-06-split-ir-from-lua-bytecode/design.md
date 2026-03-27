## Context

Lualike currently has an AST interpreter, a legacy chunk transport path created to support AST-oriented `string.dump`/`load` behavior, and a "bytecode" compiler/VM that reuses Lua opcode names while implementing a lualike-specific execution format. That approach was pragmatic while the project was AST-first and needed compatibility workarounds to pass more of the Lua test suite, but it created architectural drift: tooling, tests, and docs now mix internal IR behavior with claims about real upstream Lua bytecode compatibility.

This change is cross-cutting because it touches execution engines, serialization, stdlib integration, tooling, tests, and public behavior around binary chunks. The design must preserve reuse of the existing stdlib and core runtime semantics while separating three artifact families that currently bleed into one another:

- AST transport and interpreter execution
- `lualike_ir` internal execution and caching
- `lua_bytecode` compatibility with the vendored upstream Lua chunks

## Goals / Non-Goals

**Goals:**
- Rename and stabilize the current "bytecode" implementation as `lualike_ir`.
- Define an explicit engine boundary so AST, IR, and Lua bytecode engines share runtime services without depending on each other's internals.
- Introduce a fresh `lua_bytecode` stack that can parse, disassemble, and execute real chunks for the vendored upstream Lua release line.
- Clarify runtime and stdlib behavior so internal serialization is not presented as Lua bytecode compatibility.
- Split tests and tools by artifact family so each contract is validated independently.

**Non-Goals:**
- Reusing the current IR opcode model as the implementation model for real upstream Lua bytecode.
- Preserving backward compatibility for incorrect claims that synthetic-header AST transport is real Lua bytecode.
- Designing a new stdlib implementation per engine.
- Fully implementing the vendored upstream Lua source-to-bytecode compiler in the first migration step.

## Decisions

### Decision: Keep the current implementation as `lualike_ir` instead of deleting it

The existing compiler/VM/serializer work is useful as an internal execution format and future cache format, even though it is not real Lua bytecode. We will keep that work, rename it to `lualike_ir`, and treat it as a first-class internal runtime.

Why this over deletion:
- It preserves useful execution and serialization work.
- It gives the project a format optimized around lualike semantics and performance.
- It prevents pressure to distort a real upstream Lua implementation around existing IR assumptions.

Alternatives considered:
- Delete the current implementation and restart from nothing. Rejected because it throws away useful infrastructure and leaves no internal compiled path.
- Continue calling the current implementation "bytecode". Rejected because it preserves the architectural confusion that caused the current drift.

### Decision: Separate runtime artifact families at the module boundary

The codebase will distinguish AST transport, `lualike_ir`, and `lua_bytecode` as separate artifact families with separate loaders, serializers, tools, and tests.

Why this over a shared "bytecode" layer:
- The three artifact families have different compatibility promises.
- Success in one family must not imply compatibility in the others.
- It makes tests, docs, and tooling honest about what they validate.

Alternatives considered:
- Keep one shared bytecode namespace and document differences informally. Rejected because the current codebase already shows that naming discipline alone is not enough.

### Decision: Reuse stdlib through an engine boundary, not by sharing engine internals

The stdlib will remain shared, but engine-specific behavior will be requested through an explicit engine/runtime interface. Engine-specific code will not be allowed to leak into stdlib implementations.

The engine boundary must cover:
- loading and executing compiled artifacts
- engine-specific dump/load behavior
- debug metadata lookup
- engine-specific closure/chunk construction entry points

Why this over a separate stdlib per engine:
- Duplicating the stdlib would create a large maintenance burden and semantic drift.
- Most stdlib behavior is shared and should stay shared.
- The real problem is coupling level, not stdlib reuse itself.

Alternatives considered:
- Duplicate the stdlib for each engine. Rejected because it solves the wrong problem.
- Keep direct stdlib dependencies on AST-era machinery. Rejected because it is the main source of architectural creep.

### Decision: Treat the current chunk serializer as legacy/internal transport

The existing chunk serializer will remain available only as legacy/internal transport for AST-oriented behavior during migration. It will no longer define the serialization contract for `lualike_ir`, and it will not be used as evidence of real upstream Lua bytecode compatibility.

Why this over immediate removal:
- Existing behavior may still depend on it during the migration.
- It allows a staged transition without breaking unrelated runtime behavior all at once.

Alternatives considered:
- Keep routing IR through the same fake Lua-header path. Rejected because it keeps the contracts mixed.
- Remove the serializer immediately. Rejected because it creates avoidable migration risk.

### Decision: Build `lua_bytecode` from real chunks upward

The fresh upstream Lua path will start with exact chunk structures, parser/decoder, disassembler, and VM execution of real upstream chunks before any source-to-bytecode compiler work. The concrete target follows the vendored stable Lua release line in `third_party/lua` instead of pinning the design to an older minor version.

Why this over compiler-first:
- Upstream `luac` output provides a direct oracle.
- It avoids baking current IR assumptions into the upstream Lua implementation.
- It validates the low-level compatibility contract before adding a compiler on top.

Alternatives considered:
- Lower AST directly into a new upstream Lua compiler first. Rejected because it would make it harder to isolate whether bugs live in lowering or runtime semantics.

### Decision: Migrate in phases with honest naming first

The first migration step is naming and boundary cleanup, not opcode expansion. The sequence is:
- rename current bytecode stack to `ir`
- add the engine boundary
- split tests/tools/contracts
- add the fresh `lua_bytecode` loader/disassembler/VM

Why this over immediate semantic fixes in place:
- It reduces confusion before new work lands.
- It avoids continuing to patch a mixed architecture while claiming a cleaner future model.

## Risks / Trade-offs

- [Migration churn across many files] → Mitigation: do renames and boundary extraction before large semantic changes so the codebase stabilizes around the new structure early.
- [Temporary coexistence of legacy chunk transport and new IR serialization] → Mitigation: document the legacy status clearly and keep tests separated by artifact family.
- [Shared stdlib boundary may be too narrow or too broad on first attempt] → Mitigation: start with minimal engine-facing capabilities and expand only when a real engine need appears.
- [Real upstream Lua compatibility work may expose semantic mismatches in shared runtime primitives] → Mitigation: validate against the vendored source and matching `lua`/`luac` binaries incrementally, starting from chunk parsing and VM execution.
- [Existing tests encode incorrect assumptions] → Mitigation: rewrite tests to state whether they target AST, `lualike_ir`, or real Lua bytecode and verify suspicious cases against upstream Lua before preserving them.

## Migration Plan

1. Rename the current `lib/src/bytecode` stack, tools, and tests into `ir` terminology.
2. Reclassify fake Lua-header chunk transport as legacy/internal behavior and stop using it as the compatibility contract for compiled execution.
3. Add the engine/runtime boundary and refactor shared stdlib entry points to depend on it.
4. Split tests and tooling into AST, `lualike_ir`, and `lua_bytecode` groups.
5. Introduce a new `lua_bytecode` module with exact chunk structures, parser/decoder, and disassembler, validated against upstream `luac` for the vendored release line.
6. Implement the real upstream Lua VM against upstream chunk output.
7. Add source-to-Lua-bytecode compilation only after chunk parsing and VM execution are proven correct.

Rollback strategy:
- The migration is staged so each phase can stop with the project still usable.
- If a later `lua_bytecode` phase stalls, the AST interpreter and `lualike_ir` runtime remain available.
- Legacy chunk transport remains in place until engine-boundary and serialization replacements are working.

## Open Questions

- Should `string.dump` remain legacy/AST-backed until real upstream chunk emission exists, or should it become engine-dependent during the migration?
- What public API, if any, should expose `lualike_ir` directly for caching or tooling?
- Should `lualike_ir` preserve Lua-inspired opcode naming for continuity, or should it be renamed more aggressively once isolated from the bytecode namespace?
- How much of the current bytecode-focused test suite should be migrated into `ir` tests versus replaced entirely with upstream-validated `lua_bytecode` tests?
