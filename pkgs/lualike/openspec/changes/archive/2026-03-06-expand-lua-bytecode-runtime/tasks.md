## 1. Audit Current Runtime Gaps

- [x] 1.1 Inventory the remaining unsupported or simplified `lua_bytecode` opcode families actually emitted by local `luac55` fixtures.
- [x] 1.2 Add explicit unsupported-op diagnostics for missing `lua_bytecode` handlers instead of generic runtime failures.

## 2. Tighten Core VM Semantics

- [x] 2.1 Refine call/top/open-result handling so `CALL`, `TAILCALL`, `VARARG`, `RETURN`, and related instructions follow upstream stack discipline more closely.
- [x] 2.2 Tighten helper semantics for arithmetic, bitwise, unary, concatenation, string comparison, and table access/store behavior where the current VM still uses simplified logic.

## 3. Expand Opcode Family Coverage

- [x] 3.1 Implement the next missing expression/runtime opcode family in `lib/src/lua_bytecode/vm.dart`, including any needed helper support.
- [x] 3.2 Implement the next missing table/object interaction family, including `SELF` or other real `luac55` output not yet supported.
- [x] 3.3 Tighten `CLOSE` / `TBC` / upvalue edge-case behavior for the supported runtime subset.

## 4. Validate Against Upstream

- [x] 4.1 Add targeted oracle-backed execution tests under `test/lua_bytecode/` for each new opcode family or semantic fix.
- [x] 4.2 Re-run the `lua_bytecode` suite plus selected `lualike_ir` and legacy chunk regression tests after the new runtime slice lands.

## 5. Document Follow-Up Boundaries

- [x] 5.1 Update contributor-facing docs to reflect the newly supported `lua_bytecode` coverage and the remaining unsupported areas, if any.
