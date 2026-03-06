## 1. Specification
- [x] 1.1 Draft execution-runtime requirement covering bytecode function calls, tail calls, and returns (with vararg prep).

## 2. Compiler Enhancements
- [x] 2.1 Lower function call expressions (including tail positions) into `CALL`/`TAILCALL` opcodes.
- [x] 2.2 Emit bytecode for return statements covering `RETURN0` and `RETURN1`.
- [x] 2.3 Lower Lua function bodies into child prototypes (`CLOSURE` emission, parameter metadata, vararg flagging).

## 3. VM Execution
- [x] 3.1 Implement `CALL` and `TAILCALL` handlers managing argument counts and result propagation.
- [x] 3.2 Execute `RETURN0`/`RETURN1` opcodes, unwinding frames and propagating values.
- [x] 3.3 Execute `CLOSURE` (prototype instantiation) and capture upvalues needed for nested functions.
- [x] 3.4 Handle `VARARGPREP`/`VARARG` so bytecode functions receive and forward varargs just like the AST interpreter.

## 4. Validation
- [x] 4.1 Add compiler unit tests for direct calls and tail calls.
- [x] 4.2 Add VM unit tests executing simple functions and tail-call behaviour.
- [x] 4.3 Add executor integration tests confirming bytecode mode matches interpreter for call-heavy scripts.
- [x] 4.4 Add tests covering function literals/closures and vararg propagation (`...` access, vararg returns).
