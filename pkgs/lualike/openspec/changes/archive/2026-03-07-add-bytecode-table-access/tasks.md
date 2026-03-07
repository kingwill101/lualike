## 1. Compiler Enhancements
- [x] 1.1 Lower `TableFieldAccess` nodes to `GETFIELD` with constant short-string keys.
- [x] 1.2 Lower `TableIndexAccess` nodes to `GETI` when the index is an integer literal, otherwise to `GETTABLE`.

## 2. VM Execution
- [x] 2.1 Implement `GETFIELD`, `GETI`, and `GETTABLE` execution in `BytecodeVm` using `Value` helpers to preserve metamethod behaviour.

## 3. Validation
- [x] 3.1 Add compiler unit tests for table field/index expressions (dynamic and literal).
- [x] 3.2 Add VM and executor tests verifying bytecode table reads match interpreter results.
