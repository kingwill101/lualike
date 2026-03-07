## 1. Compiler Enhancements
- [x] 1.1 Generate child prototypes for `FunctionBody` nodes, capturing parameters, default register layout, and vararg flags.
- [x] 1.2 Emit `CLOSURE` instructions for function declarations/expressions and bind them to locals/global targets.
- [x] 1.3 Lower `VarArg` (`...`) reads and tail vararg returns into `VARARG`/`VARARGPREP` sequences.
- [x] 1.4 Track upvalue metadata for captured locals so closure bodies can reference outer registers.

## 2. VM Execution
- [x] 2.1 Introduce bytecode call-frame management (register snapshots, program counter, prototype refs).
- [x] 2.2 Implement `CLOSURE` execution producing callable closure values with captured upvalues.
- [x] 2.3 Extend `CALL`/`TAILCALL` to invoke bytecode closures via the new frame stack.
- [x] 2.4 Handle `VARARGPREP`/`VARARG` opcodes, storing excess arguments per frame and expanding results when `...` is evaluated.

## 3. Validation
- [x] 3.1 Compiler tests covering local function definitions, nested closures, and vararg lowering.
- [x] 3.2 VM unit tests executing bytecode-defined functions (including nested closures and vararg forwarding).
- [x] 3.3 Executor integration tests demonstrating bytecode parity for closures, recursive functions, and vararg calls/returns.
