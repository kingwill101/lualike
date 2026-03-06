# Design – Full Bytecode Coverage Plan

This change enumerates the Lua 5.4 opcode inventory and defines the compiler/VM work required to support each class of behaviour.

## Grouping Strategy
- **Expression Ops**: Arithmetic, bitwise, comparison, unary, concatenation. Requires numeric coercion, metamethod fallback hooks, and string handling.
- **Environment & Variable Ops**: Register moves, upvalues, locals, closures, varargs. Depends on a register allocator and environment stack management.
- **Table Ops**: Get/set variants, table construction (`NEWTABLE`, `SETLIST`), iterators (`TFOR*`). Need integration with existing `Value`/`TableStorage` behaviour and metamethods.
- **Control Flow**: Jumps, tests, loops, `return`, call/tailcall, to-be-closed variables (`TBC`, `CLOSE`). Requires call frame model, coroutine safety, and GC barriers.
- **Meta/Builtins**: `MMBIN*`, `GETTABUP`, `SETTABUP` interplay with metamethods and library tables.
- **Auxiliary**: `EXTRAARG`, debug info emission, chunk serialization, runtime feature flags.

Each group will produce separate emitter and VM tasks plus validation steps. Dependency ordering should progress from simple to complex instructions while keeping tests incremental.

## Validation Plan
- Maintain parity suites comparing AST vs bytecode results for each added feature group.
- Expand benchmarking harness once tight loops, tables, and function calls are available.
- Update documentation (`docs/runtime.md`, `docs/cli.md`) when the bytecode engine becomes parity-complete.
