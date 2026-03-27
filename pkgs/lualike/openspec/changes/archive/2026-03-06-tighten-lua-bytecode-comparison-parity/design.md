## Context

Comparison opcodes are already part of the current `lua_bytecode` subset,
but the implementation still leans on simplified raw helpers. That leaves a
gap between "the branch runs" and "the branch matches upstream Lua
semantics," especially once comparison metamethods and error cases enter
the picture.

This change stays inside runtime semantics and validation. It should not
pull in emitter work or reopen broader table semantics beyond what
comparison needs.

## Goals / Non-Goals

**Goals:**
- Tighten equality and ordering behavior for the comparison opcodes in the
  current runtime subset.
- Add oracle-backed fixtures for raw comparisons, supported metamethod
  comparisons, and explicit unsupported/error cases.
- Update the roadmap matrix so comparison parity is tracked separately from
  table parity.

**Non-Goals:**
- Implementing coroutine behavior.
- Building the source emitter.
- Broadening table constructor/list semantics beyond what comparisons
  require.

## Decisions

### Decision: Keep comparison parity separate from general table parity

Comparison semantics have enough distinct upstream rules that they deserve
their own change.

Why:
- The rules for `__eq`, `__lt`, and `__le` are independent from table
  constructor concerns.
- Isolating them makes oracle tests and regressions easier to interpret.

### Decision: Preserve the upstream test-and-jump contract

Any parity work must keep the current comparison opcode control-flow shape
compatible with real upstream chunks.

Why:
- In Lua bytecode, the comparison opcodes are not free-standing boolean
  producers.
- The runtime already models that control-flow pattern and the parity work
  should tighten semantics without regressing it.

### Decision: Make unsupported comparison cases fail explicitly

If a comparison path remains outside the current supported subset, the VM
should keep failing with a `lua_bytecode` diagnostic rather than silently
falling back to unrelated host behavior.

Why:
- Explicit failure is safer than false compatibility claims.
- It keeps the roadmap matrix honest.

## Risks / Trade-offs

- [Metamethod parity may interact with shared `Value` semantics] ->
  Mitigation: prove behavior with upstream fixtures before lifting helpers
  into broader shared code.
- [It is easy to conflate raw equality and metamethod equality] ->
  Mitigation: add separate fixtures for each path.

## Handoff

When this change is complete, continue with `add-coroutine-support`.
