# Add Bytecode Support for Bitwise, Comparison, and Unary Expressions

## Why
- The current bytecode pipeline only supports `+/-/*//` binary expressions, leaving bitwise operators, comparisons, and unary operations to fall back on the AST interpreter.
- Bitwise workloads and conditional logic are common in Lua scripts and benchmarks; parity requires emitter and VM support for these opcodes.
- Building out these expression forms unlocks the next tranche of compatibility tests and prepares the ground for metamethod fallback handling.

## What Changes
- Extend the bytecode compiler to lower bitwise (`band`, `bor`, `bxor`, shifts), comparison (`eq`, `lt`, `le`, immediate/constant variants), and unary (`not`, `unm`, `len`, `bnot`) expressions into the appropriate Lua 5.4 opcodes.
- Enhance the bytecode VM to interpret the newly emitted opcodes, including truthiness semantics and numeric coercion consistent with the AST interpreter.
- Add regression tests that exercise the compiler output and VM execution paths, plus integration tests via `executeCode` in bytecode mode.

## Impact
- Scripts using bitwise logic, comparisons, and unary operators will execute under the bytecode engine without falling back to the AST interpreter.
- We move closer to full opcode coverage identified in the planning change, enabling future metamethod and control-flow work.
