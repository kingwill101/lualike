## Why

The direct `lua_bytecode` emitter now covers the main structured and
function-definition subsets, but it still rejects table-constructor
expressions and non-identifier assignment targets. Those two gaps block a
large amount of ordinary Lua source from the emitted bytecode path.

## What Changes

- Extend direct source -> `lua_bytecode` lowering to support supported
  table-constructor expressions, including contiguous array-style entries
  and keyed field entries inside the current runtime envelope.
- Extend direct source -> `lua_bytecode` lowering to support assignment
  targets such as `t.x = v` and `t[i] = v` for the supported expression
  subset.
- Keep still-unsupported constructor or assignment forms explicitly
  diagnostic until their runtime semantics are backed by tests.
- Add focused emitter and source-engine tests covering constructors,
  field/index stores, and stable opcode families such as `NEWTABLE`,
  `SETFIELD`, `SETTABLE`, `SETI`, and `SETLIST`.

## Capabilities

### New Capabilities
- None.

### Modified Capabilities
- `lua-bytecode-emitter`: expand the supported source subset to include
  table constructors and non-identifier assignment targets.

## Impact

- Affected code: `lib/src/lua_bytecode/emitter.dart`,
  `lib/src/lua_bytecode/builder.dart`, and the `lua_bytecode` emitter
  tests
- Affected specs: `openspec/specs/lua-bytecode-emitter/spec.md`
- Validation: focused `lua_bytecode` emitter tests plus the broader
  `test/lua_bytecode` suite
