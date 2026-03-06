# Add Bytecode Support for Lua `for` Loops

## Why
- Numeric `for` loops (`for i = start, stop, step do ... end`) and generic `for` loops (`for k, v in iterator do ... end`) still fall back to the AST interpreter because the bytecode compiler/VM do not emit or execute `FORPREP`, `FORLOOP`, `TFORPREP`, `TFORCALL`, and `TFORLOOP`.
- Many real-world scripts (including the Lua test suite) rely heavily on these constructs; without them, bytecode mode cannot run benchmarks or core language features efficiently.
- Branching opcodes are already implemented, so enabling loop opcodes is the next logical milestone in the control-flow roadmap before tackling function call support.

## What Changes
- Extend the compiler to lower numeric `for` loops and generic iterator loops into the corresponding Lua 5.4 opcodes, managing register layout for loop control variables.
- Update the bytecode VM to execute the loop opcode family, respecting Lua semantics for integer/float loops, iterator results, and metamethod-driven iteration.
- Add regression tests (compiler, VM, executor) covering forward/backward numeric loops, custom step values, iterator-based loops, and metamethod-backed iteration.

## Impact
- Bytecode mode gains parity with the AST interpreter for `for` loops, unlocking large subsets of the Lua test suite and improving performance for loop-heavy scripts.
- Provides the necessary foundation before introducing bytecode function call handling, ensuring loop constructs function correctly inside future bytecode-compiled functions.
