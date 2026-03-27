## Context

`lua_bytecode` is now a separate runtime with real chunk parsing,
disassembly, routing, and an initial executable VM slice. That slice is
deliberately narrow: it is good enough for constants, globals, basic
calls, closures, simple loops, varargs, and a few `luac55` fixtures, but
it still treats several upstream contracts as simplified cases. The most
important remaining gaps are arithmetic/metamethod parity, broader opcode
coverage, stricter open-result/top handling, and clearer unsupported-op
behavior when a chunk falls outside the current VM envelope.

This follow-up is still cross-cutting inside the `lua_bytecode` path
because the work touches the VM dispatcher, frame model, helper semantics,
oracle fixtures, and documentation. It should not reopen the old
architecture question: AST transport, `lualike_ir`, and `lua_bytecode`
already have separate boundaries and must stay that way.

## Goals / Non-Goals

**Goals:**
- Expand the `lua_bytecode` VM to support the next high-value upstream
  opcode families used by real `luac55` output.
- Replace simplified runtime behavior with Lua-shaped semantics where the
  current VM is still approximating control flow or stack usage.
- Increase oracle-backed execution coverage so each newly supported area is
  proven against upstream-generated chunks.
- Make unsupported instructions fail explicitly and diagnostically instead
  of degrading into confusing runtime behavior.

**Non-Goals:**
- Reintroducing old IR semantics or compiler assumptions into
  `lua_bytecode`.
- Implementing source-to-`lua_bytecode` emission in this change.
- Making `lua_bytecode` the default engine in this change.
- Solving full coroutine yield/resume parity unless a specific opcode path
  implemented here requires it.

## Decisions

### Decision: Expand coverage by upstream opcode family, not by random failing script

Work will be grouped by coherent runtime families:
- arithmetic, bitwise, unary, and concatenation behavior
- table access/store helpers and `SELF`
- call/top/open-result discipline
- close/tbc and upvalue edge cases
- explicit unsupported-op diagnostics

Why this over ad-hoc script chasing:
- It keeps the VM architecture readable.
- It aligns implementation with `lopcodes.h` / `lvm.c`.
- It makes oracle fixtures much easier to maintain.

### Decision: Treat current VM helpers as replaceable, not canonical

The initial VM helper layer is useful scaffolding, but it is not the
final semantic source of truth. Helpers for arithmetic, string handling,
comparisons, and table operations should be tightened when upstream Lua
requires different behavior.

Why this over preserving the current helpers:
- Some helper behavior is intentionally simplified.
- The runtime now has enough real chunk coverage that upstream contracts
  should drive helper semantics directly.

### Decision: Add unsupported-op diagnostics as a first-class runtime behavior

When a chunk hits an opcode or semantic path not yet implemented, the VM
should fail with a precise `lua_bytecode` error that names the opcode and
context, instead of falling through to generic runtime errors.

Why this over silent partial behavior:
- It keeps compatibility claims honest.
- It shortens the loop for adding new opcode families.
- It prevents confusing regressions where a missing opcode looks like a
  table or arithmetic bug elsewhere.

### Decision: Keep tests oracle-backed and minimal

New execution coverage will continue to compile small fixtures with the
tracked `luac55` binary and compare runtime results against upstream Lua
behavior. Each fixture should isolate a single semantic family.

Why this over larger integrated scripts:
- Small fixtures localize failures.
- They document the intended opcode contract directly.
- They make it easier to tell whether the bug is in parsing, dispatch, or
  helper semantics.

## Risks / Trade-offs

- [Current VM frame model may still hide stack-discipline bugs] → Mitigation:
  expand tests around open-result `CALL` / `VARARG` / `RETURN` flows before
  broadening more opcode handlers.
- [Metamethod parity can leak AST/Value-layer assumptions into bytecode
  semantics] → Mitigation: validate each helper against upstream fixtures
  instead of assuming the shared `Value` behavior is automatically correct.
- [Opcode expansion can outpace diagnostics] → Mitigation: land explicit
  unsupported-op errors in the same slice as any new family work.
- [Old planning docs still say “Lua 5.4” in places] → Mitigation: keep this
  change scoped to the current vendored stable release line and update
  contributor-facing docs when touched.

## Migration Plan

1. Audit the current VM and list the highest-value unsupported or
   simplified opcode families actually emitted by `luac55`.
2. Tighten shared helper semantics and frame handling where existing code
   is still approximate.
3. Implement one opcode family at a time with targeted upstream fixtures.
4. Add explicit unsupported-op diagnostics for what still remains.
5. Re-run the dedicated `lua_bytecode` suite plus a small regression set
   for `lualike_ir` and legacy chunk routing after each slice.

Rollback strategy:
- Keep changes localized to `lib/src/lua_bytecode/` and its dedicated
  tests.
- If a family expansion causes regressions, revert that family’s handlers
  without touching the already-proven routing/parser split.

## Open Questions

- Which remaining `luac55` opcode families are the best next milestone
  after the current subset: metamethod-heavy expressions, `SELF`, or
  stricter close/tbc semantics?
- Do we want a dedicated helper layer for opcode semantics that mirrors
  upstream `lvm.c` structure more closely than the current inline helper
  style?
- Should unsupported-op diagnostics include the source line / prototype
  name immediately, or is opcode name plus `pc` enough for now?
