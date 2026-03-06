# Lua Bytecode Roadmap

## Current State

`lua_bytecode` is now a real runtime path, not a renamed IR path. The
parser, disassembler, loader, and VM all operate on real upstream Lua 5.5
chunks. The missing work is no longer "add a bytecode system"; it is
"tighten semantic parity and then add a direct source emitter."

The important current constraint is that opcode handler presence is not the
same thing as compatibility. The VM has explicit handlers for the current
opcode table, but several families are still only partially aligned with
upstream semantics or only lightly covered by oracle-backed tests.

## Architecture Decision

Use a shared front-end analysis layer and separate backends:

```text
Lua source
  -> AST
  -> shared semantic analysis
       - scope / locals
       - upvalues
       - vararg shape
       - close slots
       - loop / jump metadata
  -> lualike_ir emitter
  -> lua_bytecode emitter
```

Do not route source compilation through:

```text
AST -> lualike_ir -> lua_bytecode
```

`lualike_ir` and `lua_bytecode` have different contracts. Lowering IR into
real Lua bytecode would either deform the IR design or force a second
repair-style compiler pass.

## Coverage Matrix

| Family | Status | Notes | Evidence |
| --- | --- | --- | --- |
| Chunk header parsing and model decoding | Supported | Real 5.5 sentinels, constants, debug metadata, and instruction packing are covered. | `test/lua_bytecode/model_test.dart`, `test/lua_bytecode/parser_test.dart` |
| Runtime routing | Supported | Real upstream chunks route to `lua_bytecode`; IR and legacy AST artifacts do not. | `test/lua_bytecode/runtime_selection_test.dart` |
| Loads, constants, locals, upvalues, closures | Supported subset | Good enough for the current oracle fixtures. | `test/lua_bytecode/execution_test.dart` |
| Calls, returns, varargs, open-result flow | Supported subset | Core `CALL` / `RETURN` / `TAILCALL` / `VARARG` paths are covered. | `test/lua_bytecode/execution_test.dart` |
| Numeric and generic loops | Supported subset | Numeric `for`, generic `for`, and close-slot subset are covered. | `test/lua_bytecode/execution_test.dart` |
| Arithmetic, bitwise, unary, concat, `SELF` | Supported subset | Includes `MMBIN*` arithmetic fallback for the covered operations. | `test/lua_bytecode/execution_test.dart` |
| Basic table access/store/constructor ops | Supported subset | Raw `GET*`/`SET*`, `SELF`, table/function `__index` / `__newindex`, contiguous constructors, and large `SETLIST` / `EXTRAARG` constructors are now covered by oracle-backed fixtures. | `lib/src/lua_bytecode/vm.dart`, `test/lua_bytecode/execution_test.dart` |
| Table metatable behavior and table length semantics | Partial | Supported `__index` / `__newindex`, contiguous and prefix-boundary table length, dictionary length (`#t == 0`), and table `__len` are covered. `NEWTABLE` hash-size hints and broader edge cases are still unproven. | `lib/src/lua_bytecode/vm.dart`, `test/lua_bytecode/execution_test.dart`, local `luac55` fixture audit |
| Comparison metamethods and ordering parity | Supported subset | Raw `EQ`, `EQK`, and `EQI` semantics are aligned for the tracked subset; table `__eq`, `__lt`, and `__le` are covered for direct and immediate order comparisons, and invalid order cases now fail with upstream-style compare errors instead of silently returning `false`. Broader exotic type-metatable cases are still unproven. | `lib/src/lua_bytecode/vm.dart`, `test/lua_bytecode/execution_test.dart`, local `luac55` fixture audit |
| Coroutines and yield / resume behavior | Missing | The coroutine library change exists separately and is still in progress. | `openspec/changes/add-coroutine-support` |
| Source -> `lua_bytecode` emission | Missing | `lua_bytecode` currently loads binary chunks; it does not compile source. | `lib/src/lua_bytecode/runtime.dart`, `lib/src/config.dart` |
| Source-engine integration and real `string.dump` for emitted chunks | Missing | No direct source engine mode or emitted-function dump path yet. | Runtime / config audit |

## Change Sequence

### Runtime Parity Lane
1. `tighten-lua-bytecode-table-parity`
2. `tighten-lua-bytecode-comparison-parity`
3. `add-coroutine-support`

### Source Emitter Lane
1. `build-lua-bytecode-emitter-foundation`
2. `add-lua-bytecode-emitter-expressions`
3. `add-lua-bytecode-emitter-control-flow`
4. `integrate-lua-bytecode-source-engine`

## Sequence Rules

- Complete the runtime parity lane before claiming broad upstream chunk
  compatibility.
- The emitter lane may begin once the runtime is stable enough to execute
  the emitted subset under oracle-backed tests.
- Every change should end by naming its successor explicitly so the roadmap
  stays linear instead of devolving into another generic "bytecode" bucket.
