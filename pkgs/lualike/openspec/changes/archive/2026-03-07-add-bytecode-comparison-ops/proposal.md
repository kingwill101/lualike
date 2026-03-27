# Add Bytecode Support for Constant/Immediate Comparisons

## Why
- The bytecode compiler currently emits only register/register comparison opcodes. Lua 5.4 provides constant (`EQK`) and immediate (`EQI`, `LTI`, etc.) variants that avoid extra constant loads.
- Lack of support prevents bytecode parity for common comparisons against literals and hinders future control-flow lowering.
- Implementing these opcodes now leverages the existing `NumberUtils` work and continues closing the gap to Lua's full opcode set.

## What Changes
- Detect literal operands in comparison expressions and lower them to the appropriate constant/immediate opcodes.
- Extend the bytecode VM to execute `EQK`, `EQI`, `LTI`, `LEI`, `GTI`, and `GEI`, sharing the same coercion and truthiness semantics as the AST interpreter.
- Add regression tests for compiler output, VM execution, and executor parity when comparing against numeric and string literals.

## Impact
- Reduces register pressure for frequent literal comparisons and brings bytecode behaviour closer to Lua reference semantics.
- Creates the foundation for lowering `TEST`/branch instructions that depend on these opcode forms.
