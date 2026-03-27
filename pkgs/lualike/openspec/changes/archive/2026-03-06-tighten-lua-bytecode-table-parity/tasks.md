## 1. Refresh The Gap Inventory

- [x] 1.1 Update the table rows in `openspec/lua_bytecode_roadmap.md` with
      the exact supported, partial, and unsupported cases confirmed by
      local `luac55` fixtures.

## 2. Tighten Runtime Semantics

- [x] 2.1 Audit and tighten the `lua_bytecode` helpers for table access and
      store operations (`GET*`, `SET*`, `SELF`) against upstream behavior.
- [x] 2.2 Tighten `NEWTABLE`, `SETLIST`, and `EXTRAARG` handling for the
      constructor patterns emitted by `luac55`.
- [x] 2.3 Tighten `LEN` for supported table cases and explicit unsupported
      paths.

## 3. Validate Against Upstream

- [x] 3.1 Add oracle-backed fixtures under `test/lua_bytecode/` for table
      access/store, constructors/list writes, and `LEN`.
- [x] 3.2 Run the dedicated `lua_bytecode` suite plus the IR and legacy
      chunk regression set after the table slice lands.

## 4. Update Documentation

- [x] 4.1 Update contributor-facing docs to reflect the improved table
      coverage and any remaining unsupported areas.

## Next Change

- After completing this change, continue with
  `tighten-lua-bytecode-comparison-parity`.
