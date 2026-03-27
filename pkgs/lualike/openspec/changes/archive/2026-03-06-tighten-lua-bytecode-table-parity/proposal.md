## Why

Basic table opcodes now execute in `lua_bytecode`, but they still rely on
thin helper semantics and a narrow oracle corpus. Before we broaden
compatibility claims or build a source emitter, table behavior needs a
dedicated parity pass.

## What Changes

- Tighten `lua_bytecode` table access, store, constructor, list, and length
  semantics to better match the tracked upstream Lua release line.
- Expand oracle-backed fixtures for `GET*`, `SET*`, `NEWTABLE`, `SETLIST`,
  `EXTRAARG`, `SELF`, and `LEN` behavior.
- Document the supported and still-unsupported table cases in the roadmap
  so follow-on changes can target the remaining gaps precisely.

## Capabilities

### New Capabilities
- None.

### Modified Capabilities
- `lua-bytecode-runtime`: broaden the runtime contract to cover table and
  table-length semantics more faithfully for real upstream chunks.

## Impact

- Affected code: `lib/src/lua_bytecode/vm.dart`, shared value helpers if
  required, and `test/lua_bytecode/`
- Affected specs: `openspec/specs/lua-bytecode-runtime/spec.md`
- Tracking: `openspec/lua_bytecode_roadmap.md`
