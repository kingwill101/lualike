## Why
Bytecode mode still lacks support for Lua table constructors, forcing scripts that use `{}` literals, array-style initialisers, or keyed fields to fall back to the AST interpreter. This blocks many real-world programs and prevents us from running the Lua test suite entirely under the bytecode engine.

## What Changes
- Extend the bytecode compiler to lower table constructor expressions into `NEWTABLE`, `SETLIST`, `SETTABLE`, and related opcodes with correct sizing hints and `EXTRAARG` handling.
- Update the VM to instantiate tables with array/hash capacities, populate sequential elements via `SETLIST`, and apply keyed assignments in order.
- Add regression tests (compiler, VM, parity) covering empty tables, mixed array/hash literals, nested constructors, and vararg expansion inside constructors.

## Impact
- Capability: `execution-runtime`
- Key modules: `lib/src/bytecode/compiler.dart`, `lib/src/bytecode/vm.dart`, table-related tests.
