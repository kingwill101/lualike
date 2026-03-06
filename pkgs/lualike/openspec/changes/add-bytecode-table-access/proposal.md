# Add Bytecode Support for Table Read Operations

## Why
- Bytecode currently cannot load values from tables; any expression like `t[i]` or `t.key` falls back to the AST interpreter.
- Lua scripts lean heavily on table lookups, and many upcoming opcodes (`SELF`, branching) depend on reliable `GETTABLE`/`GETFIELD`/`GETI` behaviour.
- Implementing table reads lays the groundwork for future assignment (`SETTABLE`) and iterator support.

## What Changes
- Extend the compiler to lower `TableIndexAccess` and `TableFieldAccess` nodes into `GETTABLE`, `GETI`, and `GETFIELD` opcodes, using constant/immediate variants when possible.
- Update the bytecode VM to execute the new opcodes with metamethod-aware semantics by delegating to the existing `Value` table logic.
- Add regression tests covering dynamic, numeric, and string-keyed table reads in both unit and integration layers.

## Impact
- Bytecode mode can evaluate common table reads without fallback, bringing it closer to parity with the interpreter.
- Enables future work on method calls (`SELF`), setters, and loop lowering that rely on efficient table access.
