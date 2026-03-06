# Extend Bytecode Coverage to Full Lua 5.4 OpCode Set

## Why
- The partial emitter/VM currently supports only literals, identifier lookup, and basic arithmetic. Full parity with the AST interpreter requires lowering and executing the entire Lua 5.4 opcode set.
- Comprehensive opcode support is a prerequisite for benchmarking, compatibility testing, and eventually making the bytecode engine the default execution path.
- Having a scoped backlog of emission and execution tasks keeps the implementation organised and avoid missing critical semantics (control flow, functions, varargs, metamethods, etc.).

## What Changes
- Catalogue all Lua 5.4 opcodes and map them to compiler/VM responsibilities in discrete work items.
- Define the sequencing for emitter and VM enhancements, including support tooling (register allocation, environment handling, debug info).
- Ensure the plan includes validation tasks (unit/integration tests, parity runs, benchmarks) to prove feature completeness.

## Impact
- Provides a structured roadmap to finish bytecode support without ad-hoc guessing.
- Clarifies dependencies between emitter and VM work so implementation can proceed incrementally but with full coverage in mind.
- Sets expectations for verification effort required to maintain Lua compatibility.
