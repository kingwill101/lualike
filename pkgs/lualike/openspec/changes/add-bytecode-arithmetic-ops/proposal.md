# Add Bytecode Support for Modulo, Floor Division, and Exponent Arithmetic

## Why
- Bytecode currently rejects `%`, `//`, and `^` expressions, forcing the interpreter fallback even in simple numeric scripts.
- Lua scripts and stdlib functions (e.g., math utilities) rely on these operators; missing bytecode parity blocks broader coverage.
- Enabling these ops keeps the arithmetic surface aligned with the AST runtime and leverages existing `NumberUtils` semantics introduced earlier.

## What Changes
- Extend the bytecode compiler to lower binary expressions using `%`, `//`, and `^` into the appropriate Lua 5.4 opcodes.
- Update the bytecode VM to execute `MOD`, `IDIV`, and `POW` using `NumberUtils` helpers so coercion, division-by-zero handling, and BigInt behaviour match the interpreter.
- Add regression tests for compiler output, VM execution, and `executeCode` integration covering numeric coercion scenarios.

## Impact
- Scripts using modulo, floor division, or exponentiation run entirely in bytecode mode without falling back.
- Numeric behaviour stays consistent across execution engines thanks to shared `NumberUtils` helpers.
- Establishes groundwork for constant/immediate variants (`MODK`, `POWK`, `IDIVK`) in a later change.
