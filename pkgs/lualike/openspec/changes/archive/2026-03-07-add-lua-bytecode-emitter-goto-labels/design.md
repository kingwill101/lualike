## Context

The direct `lua_bytecode` emitter already lowers branches, loops, and the
current supported function subset, but it still rejects `Label` and `Goto`
nodes even though the bytecode runtime already executes `JMP`. The next gap
is therefore mostly a compiler/fixup problem, not a VM opcode problem.

The main constraint is correctness of label resolution. The emitter must
not silently accept gotos that fail the visible-label rules for the
supported subset, and it must keep the direct AST -> `lua_bytecode`
contract rather than routing through `lualike_ir`.

## Goals / Non-Goals

**Goals:**
- Add emitter support for forward and backward goto fixups.
- Add label definition tracking for the supported source-bytecode subset.
- Fail explicitly for unresolved or out-of-scope gotos instead of emitting
  speculative jumps.
- Validate emitted goto/label behavior against source execution.

**Non-Goals:**
- Implement every exotic label visibility edge case in one pass if the
  existing emitter scope model cannot prove them safely.
- Broaden this change into complex function-name lowering or unrelated
  control-flow work.

## Decisions

### Decision: Reuse the structured compiler’s jump-fixup model

The emitter will extend the existing structured compiler with a label table
and pending-goto list, similar in spirit to the existing IR compiler.

Why:
- The emitter already patches loop and branch fixups.
- Labels/goto are another fixup problem, not a new runtime abstraction.

### Decision: Keep label visibility conservative

If a goto cannot be resolved inside the current supported visibility rules,
the emitter will fail explicitly instead of trying to approximate Lua’s
scope semantics.

Why:
- Silent miscompilation is worse than an honest unsupported diagnostic.
- The source-bytecode path is still opt-in and should remain explicit about
  its subset limits.

## Risks / Trade-offs

- [Forward goto resolution drifts from later label positions] ->
  Mitigation: patch jumps only after labels are defined and fail unresolved
  labels at compile completion.
- [Emitter accepts invalid goto visibility cases] ->
  Mitigation: keep the first version conservative and back it with focused
  diagnostic tests.
- [Nested scopes make label bookkeeping brittle] ->
  Mitigation: model labels and pending gotos inside the structured compiler
  instead of scattering fixups across helper methods.
