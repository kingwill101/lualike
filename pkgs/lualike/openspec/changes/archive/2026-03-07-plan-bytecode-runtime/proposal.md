# Plan Bytecode Runtime Integration

## Why
- AST interpretation in `lib/src/interpreter/interpreter.dart` struggles with tight-loop performance and hinders future optimisations.
- We want a bytecode backend that reuses the existing runtime/stdlib surface instead of forking functionality.
- Prior txtlang work (`Sources/txtlang`) proves a stack-to-register lowering pipeline that we can adapt.

## Current State
- `executeCode` hard-wires AST execution via `Interpreter.run`.
- Stdlib, values, GC and environment helpers depend directly on the concrete `Interpreter` implementation.
- No shared abstraction exists for alternative execution engines.

## Goals
1. Define a runtime interface/mixin satisfied by both the current AST interpreter and a forthcoming bytecode VM.
2. Design a bytecode compilation pipeline (AST → emitter → chunk) inspired by txtlang while fitting Lua semantics and existing analyses (upvalues, closures, coroutines).
3. Outline the VM execution model and compatibility/test strategy so the stdlib keeps working unchanged.

## Non-Goals
- Implementing the bytecode VM or compiler in this change.
- Rewriting stdlib modules or altering Lua-visible APIs beyond what the interface requires.
- Introducing JIT or native backends.

## Proposed Approach
- Inventory interpreter touchpoints (env, coroutine, GC, IO, diagnostics) to know what the shared interface must expose.
- Draft a `LuaRuntime`-style interface capturing those capabilities; update shared utilities to depend on it instead of `Interpreter` directly.
- Specify emitter and bytecode chunk design, drawing on txtlang’s `CodeEmitter`/`RegInstr` patterns but tuned for Lua value semantics, upvalues, and metamethods.
- Design VM execution flow (register layout, call frames, coroutine scheduling, error reporting) that reuses `Value`, `Environment`, GC managers, and library registry.
- Plan migration, validation, and rollout: feature toggles, benchmarking, regression parity testing.

## Dependencies & References
- Existing interpreter: `lib/src/interpreter/interpreter.dart` and mixins.
- Stdlib registration: `lib/src/stdlib/library.dart`.
- Execution entrypoint: `lib/src/executor.dart`.
- txtlang reference: `Sources/txtlang/Compiler`, `Emitters`, `VM`.

## Risks / Open Questions
- Scope creep: interface may need GC or coroutine adjustments that influence many call sites.
- Instruction set design must handle Lua-specific features (metamethods, varargs, tail calls) without exploding complexity.
- Need agreement on register vs stack bytecode and how to encode upvalues efficiently.
- Determining how much of the current interpreter can be shared vs duplicated (e.g., upvalue analyzers).

## Next Steps
- Complete tasks in `tasks.md`, socialise design with maintainers, iterate on open questions, and only then start implementation changes under a separate change-id.
