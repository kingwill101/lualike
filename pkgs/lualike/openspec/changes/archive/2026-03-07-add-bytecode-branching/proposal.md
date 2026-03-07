# Add Bytecode Support for Conditional Branching

## Why
- Bytecode currently lacks control-flow lowering, so `if`, `elseif`, `else`, `while`, and boolean short-circuit expressions still fall back to the AST interpreter.
- Enabling the Lua branching opcodes (`TEST`, `TESTSET`, `JMP`) is required to execute real-world scripts fully in bytecode mode and unlocks future lowering of logical expressions and loops.
- With arithmetic, comparisons, and table operations already available, branching is the next large gap between the bytecode and AST engines.

## What Changes
- Extend the compiler to translate `IfStatement`, `WhileStatement`, and logical expressions into sequences of `TEST`/`TESTSET`/`JMP` opcodes, managing register and jump offsets.
- Implement execution of the branching opcodes in the bytecode VM, including truthiness evaluation and program-counter adjustments.
- Add regression tests (compiler, VM, executor) covering simple if/else, nested conditionals, loops, and logical short-circuit behaviour.

## Impact
- Bytecode mode will be capable of running basic control flow without falling back to the interpreter, greatly increasing coverage.
- Lays the groundwork for lowering logical expressions and loops that depend on the branching opcodes.
