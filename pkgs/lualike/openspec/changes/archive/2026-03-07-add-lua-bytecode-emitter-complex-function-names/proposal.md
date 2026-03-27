## Why

The direct `lua_bytecode` emitter now handles simple `function name(...)`
definitions, but it still rejects dotted and method-style function names.
That leaves a common Lua source family outside the emitted subset even
though the runtime already supports the table and call semantics involved.

## What Changes

- Extend direct source -> `lua_bytecode` lowering to support dotted
  function-name definitions such as `function t.add(...) end` and
  `function t.a.b.c(...) end`.
- Extend direct source -> `lua_bytecode` lowering to support method-style
  definitions such as `function t:inc(...) end` and
  `function t.a.b:inc(...) end`.
- Preserve Lua method semantics by compiling supported method definitions
  with an implicit leading `self` parameter in the emitted child
  prototype.
- Add focused emitter and source-engine tests covering dotted and
  method-style function definitions, plus opcode-shape checks where stable.

## Capabilities

### New Capabilities
- None.

### Modified Capabilities
- `lua-bytecode-emitter`: expand the supported function-definition subset
  to include dotted table paths and method-style names.

## Impact

- Affected code: `lib/src/lua_bytecode/emitter.dart`,
  `lib/src/lua_bytecode/builder.dart`, and the `lua_bytecode` emitter
  tests
- Affected specs: `openspec/specs/lua-bytecode-emitter/spec.md`
- Validation: focused `lua_bytecode` emitter tests plus the broader
  `test/lua_bytecode` suite
