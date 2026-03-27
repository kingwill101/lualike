# Design: Bytecode Upvalue Writes and Method Assignments

## Goals
- Emit `SETUPVAL`, `SETTABUP`, and `SETTABLE` from the compiler when closures or method declarations mutate captured state.
- Update the VM so upvalue writes affect the captured slots and `_ENV` mutations respect Lua semantics.
- Maintain parity with the interpreter while avoiding additional environment copies.

## Compiler Updates
1. **Capture Analysis**
   - Extend `_PrototypeContext` to record when an identifier is captured and later assigned inside a child function.
   - Bubble this metadata up so the closing prototype emits a `SETUPVAL` descriptor alongside the existing `GETUPVAL` support.
2. **Assignment Lowering**
   - When lowering an `Assignment`, resolve each target. For targets that resolve to captured locals, emit `SETUPVAL` with the descriptor index rather than a `MOVE`.
   - For `FunctionDef` / `LocalFunctionDef`, support the interpreter’s implicit `_ENV` handling: generate the closure, then emit `SETTABUP` (globals) or `SETTABLE` (namespaced / method definitions) as needed.
   - Handle implicit `self` by injecting receiver registers before emitting a method closure assignment, mirroring interpreter semantics.
3. **ENV Writes**
   - Treat `_ENV` as an upvalue: ensure assignments like `_ENV.foo = 1` use `SETTABUP` so bytecode matches interpreter behavior.

## VM Updates
1. **SETUPVAL**
   - Store into the correct captured slot (`frame.upvalues[index]`). If the captured value is a boxed environment cell, ensure the boxed value updates.
2. **Environment Mutation**
   - Reuse `_tableSet` helpers for `SETTABUP` and method assignment writes. Maintain table modification bookkeeping for GC / metamethod correctness.
3. **Validation**
   - Guard against missing upvalue descriptors with assertions to catch compiler/VM mismatches.

## Testing Strategy
- Compiler snapshots for upvalue mutation and method declarations.
- VM execution tests mutating captured counters and invoking bytecode-defined methods.
- Executor parity tests exercising closure mutation, `_ENV` updates, and method definitions in bytecode mode.
