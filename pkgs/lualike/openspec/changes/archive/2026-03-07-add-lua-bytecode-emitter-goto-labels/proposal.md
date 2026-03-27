## Why

The direct `lua_bytecode` emitter now handles the main structured loop
forms, so the next remaining control-flow gap is label and `goto` lowering.
Without it, the source-backed bytecode engine still rejects a real Lua
control-flow family even though the runtime already supports plain jumps.

## What Changes

- Add direct source -> `lua_bytecode` lowering for labels and `goto` within
  the supported source-bytecode subset.
- Add emitter-side fixup tracking for forward and backward gotos.
- Keep unsupported cross-scope or otherwise invalid label/goto cases
  explicitly diagnostic until the emitter can prove the Lua visibility
  rules.
- Add focused tests comparing emitted goto/label behavior against source
  execution and checking unresolved-label diagnostics.

## Capabilities

### New Capabilities
- None.

### Modified Capabilities
- `lua-bytecode-emitter`: expand the supported control-flow subset to
  include labels and `goto`.

## Impact

- Affected code: `lib/src/lua_bytecode/emitter.dart`, possibly
  `lib/src/lua_bytecode/builder.dart`, and
  `test/lua_bytecode/emitter_control_flow_test.dart`
- Affected specs: `openspec/specs/lua-bytecode-emitter/spec.md`
- Validation: emitter control-flow tests plus the broader
  `test/lua_bytecode` suite
