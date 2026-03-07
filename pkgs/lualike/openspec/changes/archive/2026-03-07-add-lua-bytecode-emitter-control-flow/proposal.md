## Why

An expression emitter alone is not enough to run real programs. The next
slice needs to add statements, control flow, functions, and closure-related
bytecode so the source emitter can handle meaningful program structure.

## What Changes

- Extend the `lua_bytecode` emitter to cover branches, loops, returns,
  supported function bodies, closures, and upvalue-aware control flow.
- Add fixup and analysis support for jumps, loop layout, scope lifetimes,
  and closure metadata.
- Validate emitted control-flow chunks by executing them through the
  `lua_bytecode` runtime and comparing against source behavior.

## Capabilities

### New Capabilities
- None.

### Modified Capabilities
- `lua-bytecode-emitter`: broaden emitted source coverage from isolated
  expressions to structured control flow and supported functions.

## Impact

- Affected code: emitter lowering, label/fixup infrastructure, scope and
  upvalue analysis helpers, and emitter tests
- Affected specs: `openspec/specs/lua-bytecode-emitter/spec.md`
- Validation: emitted control-flow fixtures plus source/runtime comparisons
