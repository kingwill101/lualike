## Context

The `lua_bytecode` VM already dispatches the table opcode family, but the
current behavior is still closer to "good enough for the first fixtures"
than to "table semantics we can trust broadly." The main weak points are
constructor sizing/list behavior, table access/store edge cases, and `LEN`
for tables and `__len`.

This change is intentionally limited to runtime semantics and oracle
coverage. It should not introduce source emission, reopen IR concerns, or
change the current engine-selection boundaries.

## Goals / Non-Goals

**Goals:**
- Tighten the semantics of `GETTABUP`, `GETTABLE`, `GETI`, `GETFIELD`,
  `SETTABUP`, `SETTABLE`, `SETI`, `SETFIELD`, `NEWTABLE`, `SETLIST`,
  `EXTRAARG`, `SELF`, and `LEN`.
- Add small upstream-backed fixtures that isolate each table family.
- Refresh the roadmap matrix so table behavior is no longer a vague
  "partial" bucket.

**Non-Goals:**
- Implementing comparison metamethod parity.
- Implementing coroutine yield/resume behavior.
- Adding AST -> `lua_bytecode` emission.

## Decisions

### Decision: Treat table semantics as a dedicated family

Table behavior is a large enough parity surface that it should be tracked
as its own change rather than folded into generic runtime cleanup.

Why:
- Table semantics affect many other opcode families indirectly.
- Narrow fixtures are easier to reason about than one giant conformance
  script.

### Decision: Validate constructor/list behavior with real `luac55` output

`NEWTABLE`, `SETLIST`, and `EXTRAARG` should be validated with compiled
fixtures instead of inferred from current helpers.

Why:
- The operand encodings are easy to get subtly wrong.
- Upstream compiler output is the most reliable oracle for the expected
  register and list shape.

### Decision: Include `LEN` in the table parity slice

The current `LEN` fast path leaks plain `Map.length` behavior into the VM.
That is close enough to table semantics to fix in the same slice.

Why:
- Table length and constructor semantics are tightly related in Lua.
- Splitting them would leave table behavior half-correct.

## Risks / Trade-offs

- [Shared `Value` helpers may not map exactly to bytecode expectations] ->
  Mitigation: validate behavior against upstream fixtures before changing
  shared helpers.
- [Constructor/list tests can become opaque] -> Mitigation: keep fixtures
  small and tie each one to a single compiled pattern.

## Handoff

When this change is complete, continue with
`tighten-lua-bytecode-comparison-parity`.
