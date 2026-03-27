## Why

The new `lua_bytecode` runtime can now parse and execute a small,
upstream-backed subset of Lua chunks, but large parts of the vendored Lua
runtime contract are still missing. We need a focused follow-up change so
the next implementation steps expand real Lua bytecode support instead of
slipping back into IR-era shortcuts.

## What Changes

- Expand the `lua_bytecode` VM to cover the next missing upstream opcode
  families and runtime contracts.
- Add explicit parity work for arithmetic/metamethod fallback,
  concatenation, bitwise operations, and remaining table/runtime
  instructions used by real `luac` output.
- Tighten call-frame, open-result, upvalue, and close semantics where the
  current initial VM still uses simplified behavior.
- Add oracle-backed execution tests for each newly supported behavior and
  clearer failures for still-unsupported upstream instructions.
- Update contributor-facing docs so follow-up work stays aligned with the
  `lua_bytecode` vs `lualike_ir` split.

## Capabilities

### New Capabilities
- None.

### Modified Capabilities
- `lua-bytecode-runtime`: extend the real chunk runtime from the initial
  executable subset to broader upstream Lua semantics and validation.

## Impact

- Affected code: `lib/src/lua_bytecode/`, runtime loading integration, and
  oracle-backed tests under `test/lua_bytecode/`
- Affected specs: `openspec/specs/lua-bytecode-runtime/spec.md`
- Validation: local `lua55` / `luac55` fixtures and targeted regression
  suites
