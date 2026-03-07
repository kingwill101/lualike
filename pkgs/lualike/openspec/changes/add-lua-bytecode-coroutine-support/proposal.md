## Why

`lua_bytecode` can now execute a meaningful source and chunk subset, but it still cannot suspend and resume coroutine-driven bytecode. That leaves the bytecode engine behind the shared coroutine contract and blocks the next real compatibility step for source-backed `lua_bytecode`.

## What Changes

- Extend the coroutine runtime so bytecode-backed closures can be created, resumed, yielded, wrapped, inspected, and closed through the existing `coroutine` library.
- Add suspend/resume support to the `lua_bytecode` VM so yields preserve bytecode frame state, registers, open upvalues, and close behavior across resumes.
- Add oracle-backed tests for coroutine behavior with real upstream chunks and source executed through the `lua_bytecode` engine.
- Keep unsupported bytecode coroutine edge cases explicitly diagnostic instead of silently falling back to AST or `lualike_ir`.

## Capabilities

### New Capabilities
- None.

### Modified Capabilities
- `coroutine`: coroutine lifecycle semantics now apply when the executing function is backed by `lua_bytecode`, not only the AST-oriented runtime path.
- `lua-bytecode-runtime`: the runtime gains supported coroutine/yield/resume behavior for bytecode-backed closures and emitted source.

## Impact

- Affected code: `lib/src/coroutine.dart`, `lib/src/stdlib/lib_coroutine.dart`, `lib/src/lua_bytecode/vm.dart`, `lib/src/lua_bytecode/runtime.dart`, `lib/src/runtime/lua_runtime.dart`, and `test/lua_bytecode/*`.
- Affected systems: coroutine lifecycle, bytecode VM execution state, source-engine `lua_bytecode` mode, and upstream chunk validation.
