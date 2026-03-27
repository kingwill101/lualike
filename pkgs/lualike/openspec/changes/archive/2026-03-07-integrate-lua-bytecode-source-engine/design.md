## Context

The source emitter lane ends with integration, not just compilation. Until
the runtime can select the emitted `lua_bytecode` path for source, the
compiler remains a sidecar tool rather than a real engine option.

This change should make the `lua_bytecode` source path selectable and
testable while still keeping it opt-in until the supported subset is large
enough for broader use.

## Goals / Non-Goals

**Goals:**
- Add an opt-in source-execution mode that compiles source through the
  `lua_bytecode` emitter and runs it through the `lua_bytecode` runtime.
- Integrate emitted chunks with the engine boundary and relevant dump/load
  hooks.
- Add tests that prove the source engine selects the bytecode path instead
  of AST or IR.

**Non-Goals:**
- Making `lua_bytecode` the default engine in this change.
- Claiming full-source compatibility beyond the emitted subset.

## Decisions

### Decision: Keep source-bytecode mode opt-in first

The first integrated source path should be explicit in config/CLI rather
than silently replacing AST or IR execution.

Why:
- The emitted subset will still be smaller than the full language.
- Opt-in keeps compatibility claims honest.

### Decision: Integrate through the runtime boundary, not ad hoc hooks

The source-bytecode path should use the shared runtime engine boundary so
stdlib and tooling stay engine-neutral.

Why:
- The architecture split already introduced the right seam.
- Engine-specific shortcuts would recreate the original coupling problem.

## Risks / Trade-offs

- [Users may mistake opt-in source-bytecode mode for full compatibility] ->
  Mitigation: document the supported subset and keep failures explicit.
- [Dump/load integration can blur emitted and upstream-compiled chunks] ->
  Mitigation: keep format/version boundaries explicit in docs and tests.

## Handoff

When this change is complete, refresh `openspec/lua_bytecode_roadmap.md`
and start the highest-priority uncovered family left in the matrix.
