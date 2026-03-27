## 1. Add Source-Engine Selection

- [x] 1.1 Add an opt-in source engine mode that compiles source through the
      `lua_bytecode` emitter and executes it through the `lua_bytecode`
      runtime.
- [x] 1.2 Keep unsupported source subsets failing explicitly instead of
      silently falling back to AST or IR execution.

## 2. Integrate Runtime Hooks

- [x] 2.1 Integrate emitted `lua_bytecode` chunks with the runtime engine
      boundary and source loading path.
- [x] 2.2 Integrate emitted-function dump/load behavior where the supported
      subset can honor it honestly.

## 3. Validate And Document

- [x] 3.1 Add tests covering CLI/config/runtime selection for the source
      bytecode path.
- [x] 3.2 Re-run the `lua_bytecode`, `lualike_ir`, and legacy chunk
      regression suites after integration lands.
- [x] 3.3 Update the roadmap and contributor docs to describe the new
      opt-in source-bytecode mode and its limits.

## Next Change

- After completing this change, refresh `openspec/lua_bytecode_roadmap.md`
  and start the highest-priority uncovered family left in the matrix.
