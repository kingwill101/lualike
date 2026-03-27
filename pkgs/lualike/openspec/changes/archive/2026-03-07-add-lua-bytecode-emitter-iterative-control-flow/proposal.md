## Why

The direct `lua_bytecode` emitter still stops short of the most useful
remaining structured loop forms, which keeps the source-backed bytecode
engine from handling common iterator and post-test loop patterns. The next
step is to add the real Lua lowering for generic `for` and `repeat ...
until` without widening the scope to labels or `goto`.

## What Changes

- Add direct source -> `lua_bytecode` lowering for generic `for` loops in
  the supported source engine subset.
- Add direct source -> `lua_bytecode` lowering for `repeat ... until`
  loops, including the scope rule where body locals are visible to the
  terminating condition.
- Add oracle-backed tests comparing emitted loop families against source
  behavior and `luac55` opcode families where the shape is stable enough to
  matter.
- Keep labels / `goto` and other still-unsupported control-flow families
  explicitly diagnostic.

## Capabilities

### New Capabilities
- None.

### Modified Capabilities
- `lua-bytecode-emitter`: expand the supported structured control-flow
  subset to include generic iteration and post-test loops.

## Impact

- Affected code: `lib/src/lua_bytecode/emitter.dart`,
  `lib/src/lua_bytecode/builder.dart`, and the emitter control-flow tests
- Affected specs: `openspec/specs/lua-bytecode-emitter/spec.md`
- Validation: `test/lua_bytecode/emitter_control_flow_test.dart` plus the
  existing `test/lua_bytecode` suite
