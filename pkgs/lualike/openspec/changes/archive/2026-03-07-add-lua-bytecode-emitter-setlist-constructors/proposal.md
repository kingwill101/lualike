## Why

The direct `lua_bytecode` emitter now handles the basic constructor/store
subset, but it still rejects constructor shapes that need real
`SETLIST` / `EXTRAARG` lowering and a trailing open-result call such as
`{f()}`. Those forms are common in ordinary Lua source, and leaving them
unsupported keeps the emitted source engine narrower than the runtime it
already targets.

## What Changes

- Extend direct source -> `lua_bytecode` lowering to emit contiguous
  array-style constructor batches through `SETLIST` / `EXTRAARG` where
  that shape is required.
- Extend constructor lowering to support a trailing open-result call or
  method call entry such as `{f()}` or `{1, g()}` in the supported subset.
- Keep constructor forms still outside the supported subset explicitly
  diagnostic until their runtime semantics are backed by tests.
- Add focused emitter and source-engine tests covering `SETLIST`,
  `EXTRAARG`, large array constructors, and open-result constructor
  entries.

## Capabilities

### New Capabilities
- None.

### Modified Capabilities
- `lua-bytecode-emitter`: expand the supported source subset to include
  `SETLIST`-backed constructor lowering and trailing open-result
  constructor entries.

## Impact

- Affected code: `lib/src/lua_bytecode/emitter.dart`,
  `lib/src/lua_bytecode/builder.dart`, and the `lua_bytecode` emitter
  tests
- Affected specs: `openspec/specs/lua-bytecode-emitter/spec.md`
- Validation: focused `lua_bytecode` emitter tests plus the broader
  `test/lua_bytecode` suite
