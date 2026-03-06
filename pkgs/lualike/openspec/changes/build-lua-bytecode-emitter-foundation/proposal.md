## Why

`lua_bytecode` can currently load and execute real upstream chunks, but
there is no source compilation path that produces those chunks. Before we
can run source through a bytecode engine, we need a direct AST ->
`lua_bytecode` emitter foundation with shared semantic analysis and chunk
building primitives.

## What Changes

- Introduce the `lua_bytecode` emitter module and its supporting analysis
  structures.
- Define a direct source lowering path from AST through shared semantic
  analysis to `lua_bytecode`, explicitly without routing through
  `lualike_ir`.
- Add a minimal executable subset for emitted chunks so the foundation is
  testable end to end.

## Capabilities

### New Capabilities
- `lua-bytecode-emitter`: compile supported source subsets directly from AST
  into real `lua_bytecode` chunks.

### Modified Capabilities
- None.

## Impact

- Affected code: new emitter code under `lib/src/lua_bytecode/` or a nearby
  dedicated emitter namespace, shared analysis helpers as needed, and new
  emitter tests
- Affected specs: new `openspec/specs/lua-bytecode-emitter/spec.md`
- Validation: parse/disassemble/execute emitted chunks under the existing
  `lua_bytecode` runtime and compare to `luac55` behavior where practical
