## Why

Even after the emitter can compile useful source subsets, the engine will
still be hard to exercise unless source loading, dumping, and runtime
selection can use it directly. The final slice in this roadmap integrates
the emitted chunks into the normal source-execution path without making
`lua_bytecode` the default prematurely.

## What Changes

- Add opt-in source execution through the `lua_bytecode` emitter/runtime
  path.
- Extend runtime integration points such as chunk loading and function dump
  behavior so emitted `lua_bytecode` chunks behave like a first-class engine
  path.
- Add CLI/config/test coverage for selecting the source bytecode engine.

## Capabilities

### New Capabilities
- None.

### Modified Capabilities
- `lua-bytecode-emitter`: integrate emitted chunks into source execution and
  dump/load workflows.
- `runtime-engine-boundary`: extend the engine contract to accommodate
  source emission through the `lua_bytecode` path.

## Impact

- Affected code: config/CLI/runtime selection, `load` / `string.dump`
  integration points, emitter/runtime glue, and source-engine tests
- Affected specs: `openspec/specs/lua-bytecode-emitter/spec.md`,
  `openspec/specs/runtime-engine-boundary/spec.md`
- Validation: source-mode tests, emitted-chunk tests, and regression suites
