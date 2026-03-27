## 1. Specification
- [x] 1.1 Add execution-runtime requirement covering numeric and generic `for` loops in bytecode mode.

## 2. Compiler Enhancements
- [x] 2.1 Lower numeric `for` loops into `FORPREP`/`FORLOOP`, managing register allocation for control, limit, and step variables.
- [x] 2.2 Lower generic `for` loops into `TFORPREP`/`TFORCALL`/`TFORLOOP`, wiring loop variable scopes.

## 3. VM Execution
- [x] 3.1 Execute `FORPREP` and `FORLOOP`, supporting integer and float semantics identical to the interpreter.
- [x] 3.2 Execute `TFORPREP`/`TFORCALL`/`TFORLOOP`, including iterator invocation and result propagation.

## 4. Validation
- [x] 4.1 Add compiler unit tests covering numeric loops (ascending, descending, custom step).
- [x] 4.2 Add VM unit tests for numeric loops, verifying register updates and loop counts.
- [x] 4.3 Add executor integration tests confirming bytecode mode runs numeric loop scripts identically to the AST interpreter.
- [x] 4.4 Add generic-loop tests (compiler, VM, executor) validating iterator-driven behaviour.
