## Why

Lualike's current "bytecode" work mixes three different concerns: AST-oriented chunk transport, an internal Lua-inspired execution IR, and the behavior of real upstream Lua bytecode. That overlap made the existing path useful for incremental parity work, but it now blocks a correct implementation of the vendored upstream bytecode semantics and makes it hard to reason about compatibility, testing, and future optimization work.

## What Changes

- Reclassify the current bytecode compiler, VM, and serialization stack as `lualike_ir`, an internal execution format used for faster execution and serialization of lualike programs.
- Introduce a shared engine/runtime boundary so the stdlib, values, environments, tables, and metamethod behavior can be reused without depending directly on AST-specific or IR-specific machinery.
- Create a new `lua_bytecode` path for real upstream-compatible chunk structures, decoding, disassembly, execution, and later compilation based on the vendored Lua release line.
- **BREAKING** Stop presenting the current fake chunk/header path as Lua bytecode compatibility. Legacy AST/internal chunk transport remains available, but it is no longer treated as real Lua binary chunk support.
- Split tests and tooling so semantic parity, `lualike_ir`, and real upstream Lua bytecode compatibility are validated independently.
- Correct tests and documentation that currently encode IR-specific behavior or incorrect Lua bytecode assumptions.

## Capabilities

### New Capabilities
- `lualike-ir-runtime`: Define `lualike_ir` as a first-class internal execution and serialization format with its own compiler, loader, VM, and compatibility boundaries.
- `lua-bytecode-runtime`: Add a separate upstream Lua bytecode path that parses, disassembles, and executes real chunks for the vendored Lua release line according to upstream semantics.
- `runtime-engine-boundary`: Define the shared runtime and stdlib interface used by AST, IR, and upstream Lua bytecode engines so engine-specific behavior is isolated behind explicit contracts.

### Modified Capabilities
- None.

## Impact

- Affected code includes the current bytecode stack under `lib/src/bytecode/`, chunk serialization/load paths, stdlib `load`/`string.dump` behavior, bytecode tools, and bytecode-focused tests.
- Public and semi-public behavior around `string.dump`, `load`, and binary chunk handling will be clarified and partially redefined to separate internal transport from real Lua bytecode compatibility.
- The work introduces a new architecture for execution engines while preserving reuse of the existing stdlib and core runtime semantics.
- Future optimization and caching work can target `lualike_ir` directly without constraining the design of a real upstream Lua bytecode implementation.
