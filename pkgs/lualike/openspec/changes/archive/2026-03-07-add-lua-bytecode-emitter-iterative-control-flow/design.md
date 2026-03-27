## Context

The current emitter already handles `if`, `while`, numeric `for`, `break`,
simple functions, and captured upvalues, and the runtime already executes
the upstream `TFOR*` family. What is missing is the direct AST lowering for
the remaining structured loop forms that still appear as explicit
`UnsupportedError`s in the emitter: generic `for` and `repeat ... until`.

The design constraint is to stay honest about the subset boundary. This
change should extend the emitter only to the loop families that already fit
inside the proven runtime envelope, and it should keep `goto`/labels out of
scope.

## Goals / Non-Goals

**Goals:**
- Emit generic `for` loops directly to real `lua_bytecode` using the
  existing `TFORPREP` / `TFORCALL` / `TFORLOOP` runtime contract.
- Emit `repeat ... until` loops directly to real `lua_bytecode` with the
  correct body-before-condition execution order.
- Preserve the Lua scope rule where locals declared inside a repeat body are
  still visible to the terminating condition.
- Add focused execution and opcode-family tests for the new subset.

**Non-Goals:**
- Implement labels or `goto`.
- Broaden the change into unsupported table-constructor or complex
  function-name emission work.
- Add new runtime opcode support beyond what the `lua_bytecode` VM already
  executes.

## Decisions

### Decision: Lower generic `for` directly to the `TFOR*` family

The emitter will reserve the iterator/state/control/closing register block,
populate it through the existing expression emitter, and then use
`TFORPREP`, `TFORCALL`, `TFORLOOP`, and `CLOSE` in the same control-flow
shape that upstream `luac55` emits.

Why:
- The runtime already supports the `TFOR*` family.
- Matching the real bytecode pattern is more robust than inventing a custom
  structured lowering.

### Decision: Keep repeat-loop scope open through the condition

The emitter will enter one scope for the repeat body plus terminating
condition, compile the body first, then compile the condition before closing
that scope.

Why:
- Lua allows locals introduced in the repeat body to be referenced by the
  `until` condition.
- Splitting body and condition into separate scopes would silently compile
  the wrong language.

### Decision: Keep unsupported control-flow explicit

This change will remove `ForInLoop` and `RepeatUntilLoop` from the
unsupported set, but labels / `goto` and other unsupported families remain
explicit diagnostics.

Why:
- It keeps the source-bytecode boundary testable and honest.
- It avoids turning one structured-loop change into a generic control-flow
  bucket.

## Risks / Trade-offs

- [Generic `for` register layout drifts from runtime expectations] ->
  Mitigation: compare the emitted opcode family against `luac55` and execute
  emitted chunks through the existing runtime tests.
- [Repeat-loop scope is compiled too narrowly] ->
  Mitigation: add a focused test where the terminating condition references a
  local declared inside the body.
- [Break targets skip generic-for close behavior] ->
  Mitigation: route loop-exit jumps through the emitted `CLOSE` instruction
  instead of patching them after it.
