## Why

The current `lua_bytecode` VM can execute comparison opcodes, but the
behavior is still closer to raw value comparison than to full upstream
comparison semantics. We need a focused parity slice for `__eq`, `__lt`,
`__le`, and related comparison error behavior before pushing compatibility
claims further.

## What Changes

- Tighten the `lua_bytecode` comparison helpers so supported comparison
  opcodes follow upstream semantics for the tracked release line.
- Add targeted upstream-generated fixtures for equality, ordering, and
  comparison metamethod cases.
- Refresh the roadmap and contributor docs so the remaining comparison gaps
  stay explicit.

## Capabilities

### New Capabilities
- None.

### Modified Capabilities
- `lua-bytecode-runtime`: extend comparison and ordering semantics for real
  upstream chunks in the supported runtime subset.

## Impact

- Affected code: `lib/src/lua_bytecode/vm.dart`, related value/metamethod
  helpers if needed, and `test/lua_bytecode/`
- Affected specs: `openspec/specs/lua-bytecode-runtime/spec.md`
- Tracking: `openspec/lua_bytecode_roadmap.md`
