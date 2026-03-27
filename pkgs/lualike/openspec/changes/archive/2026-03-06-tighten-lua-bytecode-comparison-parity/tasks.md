## 1. Refresh The Gap Inventory

- [x] 1.1 Update the comparison rows in `openspec/lua_bytecode_roadmap.md`
      with the exact raw, metamethod, and unsupported cases confirmed by
      local `luac55` fixtures.

## 2. Tighten Runtime Semantics

- [x] 2.1 Audit and tighten equality and ordering helpers used by the
      `lua_bytecode` comparison opcodes.
- [x] 2.2 Implement or explicitly diagnose the supported comparison
      metamethod paths needed for the tracked runtime subset.
- [x] 2.3 Tighten comparison error behavior so unsupported cases fail with a
      clear `lua_bytecode` diagnostic.

## 3. Validate Against Upstream

- [x] 3.1 Add oracle-backed fixtures under `test/lua_bytecode/` for raw
      equality/order, supported metamethod comparisons, and explicit
      unsupported cases.
- [x] 3.2 Run the dedicated `lua_bytecode` suite plus the IR and legacy
      chunk regression set after the comparison slice lands.

## 4. Update Documentation

- [x] 4.1 Update contributor-facing docs to reflect the improved comparison
      coverage and any remaining unsupported areas.

## Next Change

- After completing this change, continue with `add-coroutine-support`.
