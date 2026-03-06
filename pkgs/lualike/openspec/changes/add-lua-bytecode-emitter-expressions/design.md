## Context

The emitter foundation gives us the compiler boundary and minimal chunk
generation, but it does not yet cover the expressions developers actually
write. The runtime already supports a useful subset of expression-related
bytecode families, so the next emitter slice should target that supported
runtime envelope directly.

This change stays at expression level. It should not implement statement
control flow, closure bodies, or full source-engine integration.

## Goals / Non-Goals

**Goals:**
- Compile the core expression families that map to the current runtime
  subset.
- Keep register allocation and open-result behavior consistent with the
  runtime contracts already proven in `lua_bytecode`.
- Validate emitted chunks through parse/disassemble/execute tests.

**Non-Goals:**
- Branches, loops, labels, and closure emission.
- Making `lua_bytecode` the default source engine.

## Decisions

### Decision: Match the runtime subset, not the whole language at once

Only expression families that the runtime can already execute confidently
should be emitted in this change.

Why:
- It keeps the compiler and runtime envelopes aligned.
- It avoids generating chunks for semantic paths the VM cannot yet prove.

### Decision: Compare emitted chunks by behavior first

Where exact `luac55 -l` shape is stable and useful, compare it. Where it is
not, prioritize execution behavior and parser/disassembler round-trips.

Why:
- Some register layouts can vary while still being semantically correct.
- Behavior remains the primary contract.

## Risks / Trade-offs

- [Register allocation may become entangled with future control flow] ->
  Mitigation: keep allocation local and expression-oriented in this change.
- [Table and call expressions can hide runtime gaps] -> Mitigation: only
  emit the expression families that are already inside the runtime subset.

## Handoff

When this change is complete, continue with
`add-lua-bytecode-emitter-control-flow`.
