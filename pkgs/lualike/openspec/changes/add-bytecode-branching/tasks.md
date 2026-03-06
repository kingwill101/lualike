## 1. Compiler Enhancements
- [x] 1.1 Lower `IfStatement` (with optional elseif/else) into `TEST`/`JMP` sequences.
- [x] 1.2 Lower `WhileStatement` loops using branching opcodes.
- [x] 1.3 Emit short-circuit boolean expressions (`and`/`or`) via branching to avoid unnecessary evaluation.

## 2. VM Execution
- [x] 2.1 Implement `TEST`, `TESTSET`, and `JMP` opcodes in `BytecodeVm`, updating PC and truthiness semantics.

## 3. Validation
- [x] 3.1 Add compiler unit tests for if/elseif/else and while lowering.
- [x] 3.2 Add VM unit tests covering branching execution paths (including logical short circuits).
- [x] 3.3 Add executor integration tests verifying bytecode mode runs simple control-flow programs identically to the AST interpreter.
