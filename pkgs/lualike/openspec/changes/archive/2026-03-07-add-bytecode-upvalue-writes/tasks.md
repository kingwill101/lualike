## 1. Compiler Enhancements
- [x] 1.1 Track captured locals that are written inside nested functions and expose metadata for emitting `SETUPVAL`.
- [x] 1.2 Lower assignments that target captured locals to `SETUPVAL` (including compound statements like `local f; function f() ... end`).
- [x] 1.3 Support function and method declarations that assign closures into `_ENV` or table fields, emitting `SETTABUP` / `SETTABLE` with correct implicit `self` handling.
- [x] 1.4 Ensure `_ENV` assignments in bytecode mode use upvalue/table stores instead of global fallbacks.

## 2. VM Execution
- [x] 2.1 Implement `SETUPVAL` write semantics so mutated upvalues propagate across frames.
- [x] 2.2 Route `_ENV` and table method writes through VM helpers to match interpreter behavior (including table mutation bookkeeping).
- [x] 2.3 Add targeted diagnostics (asserts/logging) to guard against missing upvalue descriptors during `SETUPVAL`.

## 3. Validation
- [x] 3.1 Compiler tests covering closure mutation, method definitions, and `_ENV` assignments.
- [x] 3.2 VM unit tests verifying upvalue writes and method calls operating purely in bytecode.
- [x] 3.3 Executor parity tests demonstrating bytecode vs AST consistency for the new scenarios.
- [x] 3.4 Run `dart test test/bytecode test/unit/executor_bytecode_parity_test.dart test/interpreter/core/executor_bytecode_test.dart`.
