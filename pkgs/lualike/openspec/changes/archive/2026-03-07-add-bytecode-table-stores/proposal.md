# Add Bytecode Support for Table Write Operations

## Why
- Table assignment (`tbl.key = v`, `tbl[i] = v`) still forces bytecode execution to fall back to the AST interpreter, limiting usefulness of bytecode mode in real programs.
- Lua’s opcode set provides `SETFIELD`, `SETTABLE`, and `SETI`, which we already track in the coverage plan; enabling them unlocks more interpreter parity and allows future control-flow lowering to assume table writes are available.
- Table writes must respect metamethods (`__newindex`) and existing Value semantics; implementing them now builds on the read-path work just delivered.

## What Changes
- Extend the bytecode compiler to lower assignments whose targets are table field/index forms into the correct store opcodes, handling integer literals via `SETI` and string fields via `SETFIELD`.
- Update the bytecode VM to execute the new store opcodes, delegating to `Value` helpers so metamethod behaviour matches the interpreter.
- Add regression tests (compiler, VM, executor) covering string and numeric table writes, including metamethod observation.

## Impact
- Bytecode mode can handle common data mutations without falling back to the AST interpreter.
- Sets the stage for lowering compound statements and method calls (`SELF`) that depend on table mutation.
