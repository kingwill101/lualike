## Context

After the expression slice, the next blocker is program structure: branches,
loops, nested functions, closure capture, and return/call shaping. This is
where the emitter needs real control-flow bookkeeping instead of local
expression-only allocation.

This change should still stay inside the emitter and its tests. It should
not yet make `lua_bytecode` the default source engine.

## Goals / Non-Goals

**Goals:**
- Emit supported statement and control-flow forms as real `lua_bytecode`.
- Reuse the shared analysis facts introduced by the foundation where
  possible.
- Validate emitted chunks by running them through the existing
  `lua_bytecode` runtime.

**Non-Goals:**
- Full engine integration for source execution.
- Solving every coroutine/yield interaction in the same slice.

## Decisions

### Decision: Build explicit fixup infrastructure

Control flow should use dedicated label and fixup support instead of
expression-layer patching tricks.

Why:
- Jumps, loops, and closure exits need a stable abstraction.
- It keeps the emitted bytecode readable and debuggable.

### Decision: Reuse shared semantic analysis for scope and upvalues

The emitter should consume common scope/upvalue facts rather than
re-deriving them ad hoc inside each statement lowering path.

Why:
- Scope and upvalue handling are compiler facts, not backend accidents.
- The same facts will matter for later integration work.

## Risks / Trade-offs

- [Control-flow lowering can expose runtime gaps] -> Mitigation: only emit
  forms that the current runtime can already execute or diagnose clearly.
- [Function emission can blur the line with engine integration] ->
  Mitigation: keep this change focused on emitted chunks and tests.

## Handoff

When this change is complete, continue with
`integrate-lua-bytecode-source-engine`.
