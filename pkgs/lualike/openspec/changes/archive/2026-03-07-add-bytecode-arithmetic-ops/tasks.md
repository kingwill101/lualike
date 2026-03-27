## 1. Compiler Support
- [x] 1.1 Extend `BytecodeCompiler` binary lowering to map `%`, `//`, and `^` to `MOD`, `IDIV`, and `POW` opcodes.

## 2. VM Execution
- [x] 2.1 Add `MOD`, `IDIV`, and `POW` opcode handling in `BytecodeVm`, delegating to `NumberUtils` for Lua-accurate semantics.

## 3. Validation
- [x] 3.1 Add compiler unit tests covering modulo, floor division, and exponent expressions.
- [x] 3.2 Add VM and `executeCode` bytecode tests verifying results and string/number coercion behaviour.
