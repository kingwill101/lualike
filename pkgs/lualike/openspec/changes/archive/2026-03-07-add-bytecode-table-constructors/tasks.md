## 1. Compiler Enhancements
- [x] 1.1 Lower table constructor expressions into `NEWTABLE` plus appropriate store opcodes while preserving evaluation order.
- [x] 1.2 Support hash-field entries (e.g., `{ foo = 1, [expr] = value }`) by reusing existing table assignment helpers during constructor lowering.
- [x] 1.3 Populate sequential array elements (including constructor literals that wrap function calls) without leaking temporary registers.
- [x] 1.4 Expand trailing function calls and `...` within constructors so all returned values populate array slots in order.
- [x] 1.5 Emit `NEWTABLE` sizing hints and split large array batches using multiple `SETLIST` instructions (with `B=0` when needed).

## 2. VM Execution
- [x] 2.1 Implement `NEWTABLE` support in the VM, allocating tables with optional array/hash hints.
- [x] 2.2 Ensure constructor execution interleaves keyed stores correctly and maintains metamethod compatibility.
- [x] 2.3 Honour `NEWTABLE` sizing hints and handle `SETLIST` with `B=0`/large batches when populating tables.

## 3. Validation
- [x] 3.1 Compiler unit tests for empty tables, array-heavy constructors, keyed fields, and mixed literal orderings.
- [x] 3.2 VM unit tests verifying constructor execution with nested tables and mixed array/hash layouts.
- [x] 3.3 Executor parity tests covering representative scripts (e.g., literal tables with sequential and keyed entries) in AST vs bytecode modes.
- [x] 3.4 Run `dart test test/bytecode test/unit/executor_bytecode_parity_test.dart test/interpreter/core/executor_bytecode_test.dart`.
