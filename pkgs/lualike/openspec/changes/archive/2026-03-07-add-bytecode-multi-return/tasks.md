## 1. Compiler Enhancements
- [x] 1.1 Support multiple expressions in `return` statements, including trailing calls/`...` that forward variable results.
- [x] 1.2 Support multi-target assignments and local declarations, propagating trailing call/vararg results across targets.
- [x] 1.3 Tighten register allocation/release so multi-result evaluation does not leak temporary registers.

## 2. VM Execution
- [x] 2.1 Verify `CALL`/`RETURN` operand handling for dynamic result counts and adjust `_storeResults` if discrepancies surface.
- [x] 2.2 Add targeted VM tests covering multi-return and assignment flows (including vararg propagation).

## 3. Validation
- [x] 3.1 Compiler unit tests for multi-value returns and assignments.
- [x] 3.2 VM unit tests exercising multi-result propagation.
- [x] 3.3 Executor parity tests ensuring bytecode matches AST for representative scripts.
- [x] 3.4 Run `dart test test/bytecode test/unit/executor_bytecode_parity_test.dart`.
