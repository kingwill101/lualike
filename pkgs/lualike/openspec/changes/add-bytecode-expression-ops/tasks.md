## 1. Compiler Enhancements
- [x] 1.1 Extend `BytecodeCompiler` to lower bitwise operators (`&`, `|`, `~`, `<<`, `>>`) into corresponding opcodes.
- [x] 1.2 Lower comparison operators (`==`, `~=`, `<`, `<=`, `>`, `>=`) with register/register operands.
- [x] 1.3 Handle unary expressions (`not`, unary minus, bitwise not, length) emitting `NOT`, `UNM`, `BNOT`, `LEN`.

## 2. VM Support
- [x] 2.1 Implement VM execution for new binary bitwise and comparison opcodes with proper coercion.
- [x] 2.2 Implement VM execution for unary opcodes and truthiness evaluation.

## 3. Validation
- [x] 3.1 Add compiler unit tests covering bitwise, comparison, and unary expression lowering.
- [x] 3.2 Add VM and `executeCode` integration tests verifying bytecode results match AST interpreter behaviour.
