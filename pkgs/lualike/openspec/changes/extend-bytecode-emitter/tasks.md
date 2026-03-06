## 1. Compiler Enhancements
- [x] 1.1 Extend `BytecodeCompiler` to lower `Identifier` nodes via `GETTABUP` and register reuse.
- [x] 1.2 Emit arithmetic opcodes for `BinaryExpression` (`+`, `-`, `*`, `/`) with correct register management.

## 2. VM Support
- [x] 2.1 Update `BytecodeVm` to execute `GETTABUP`, `ADD`, `SUB`, `MUL`, and `DIV` using the injected environment and numeric coercion.

## 3. Validation
- [x] 3.1 Add unit tests for compiler instruction sequences covering literals, identifiers, and arithmetic expressions.
- [x] 3.2 Add VM/`executeCode` regression tests demonstrating bytecode mode evaluating arithmetic against global values.
