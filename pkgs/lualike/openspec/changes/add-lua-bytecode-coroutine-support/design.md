## Context

The shared coroutine library already exposes `create`, `resume`, `yield`, `wrap`, `close`, `status`, `running`, and `isyieldable`, and those semantics are implemented for the AST runtime. The `lua_bytecode` runtime reuses the same stdlib and coroutine objects at the API boundary, but its VM still executes each invocation as a single-shot call. A `YieldException` inside bytecode currently behaves like an unstructured escape instead of a resumable suspension with preserved bytecode frame state.

The recent emitter work changed the priority of this gap. Source can now run through `lua_bytecode`, so coroutine support is no longer an isolated chunk-runtime concern; it is a correctness gap in the engine mode itself.

## Goals / Non-Goals

**Goals:**
- Support coroutine lifecycle semantics for bytecode-backed closures and emitted source executed through `lua_bytecode`.
- Preserve bytecode frame state across yields, including registers, program counters, open upvalues, open-result bookkeeping, and closeable resources in the supported subset.
- Reuse the existing coroutine library surface and thread values so stdlib callers do not need engine-specific branching.
- Validate behavior with both source-engine tests and upstream-generated chunk fixtures.

**Non-Goals:**
- Rewriting the shared coroutine API or introducing a second public thread type for bytecode.
- Claiming full Lua 5.5 coroutine parity for every continuation opcode and edge case in one change.
- Routing coroutine-capable source through `lualike_ir` or AST as a hidden fallback when `lua_bytecode` is selected.

## Decisions

### Reuse the existing `Coroutine` abstraction instead of introducing a bytecode-only thread type

The stdlib and runtime boundary already treat coroutine values as engine-neutral thread objects. Adding a separate `LuaBytecodeCoroutine` public type would duplicate lifecycle handling and leak engine details into the stdlib contract.

Instead, the existing `Coroutine` object will be generalized to support an engine-owned continuation payload for bytecode execution. The AST path keeps using its current statement/program-counter model; the bytecode path stores resumable VM state in that continuation slot.

Alternative considered:
- Add a bytecode-specific coroutine type and branch inside `lib_coroutine.dart`.
  - Rejected because it splits the public thread model and pushes engine knowledge into shared stdlib code.

### Model bytecode suspension as an explicit VM continuation snapshot

The bytecode VM needs to preserve more than a single function call result. A yield can happen with nested bytecode calls active, open upvalues still referenced, and `CLOSE` / `TBC` work still pending. The design will introduce a bytecode continuation snapshot that stores the suspended frame stack and the resume handoff state.

That snapshot should include:
- active bytecode frames
- each frame's `pc`, registers, open-result / top markers, and closeable-register state
- references to open upvalues and closures
- yielded values and the pending resume payload boundary

Alternative considered:
- Reconstruct bytecode frames from closures and source debug metadata after yield.
  - Rejected because it is fragile, loses runtime register state, and does not map cleanly to open upvalues or pending `CLOSE` work.

### Continue to use the existing `YieldException` as the public suspension signal

`coroutine.yield` already throws `YieldException`, and the AST runtime already depends on that contract. The bytecode VM will catch this exception at the VM boundary, convert it into a bytecode continuation snapshot, mark the coroutine suspended, and hand the yielded values back through the existing coroutine resume machinery.

Alternative considered:
- Add a separate bytecode-only yield signal.
  - Rejected because it would fork control-flow handling and make mixed engine call stacks harder to reason about.

### Scope the first implementation to the supported bytecode subset and fail explicitly beyond it

The immediate value is supporting coroutine behavior for the already-supported chunk and emitter subset. If a bytecode coroutine reaches a path the runtime still cannot suspend or resume correctly, the runtime should fail with an explicit `lua_bytecode` coroutine diagnostic instead of corrupting state or silently falling back to another engine.

Alternative considered:
- Delay the change until every coroutine-related opcode and edge case is fully implemented.
  - Rejected because it blocks a high-value compatibility step and is unnecessary for the current supported subset.

## Risks / Trade-offs

- **[Risk] Mixed AST and bytecode call stacks can leave coroutine status or current-environment state inconsistent.** → Keep coroutine ownership in the shared runtime boundary and restore current coroutine/environment around every suspend and resume boundary.
- **[Risk] Preserving bytecode frame state across yields can leak open resources or fail to run `CLOSE` correctly.** → Store closeable-register state in the continuation snapshot and add targeted tests for yield/resume around close paths in the supported subset.
- **[Risk] Bytecode coroutine support may accidentally widen compatibility claims too far.** → Keep the spec and tests scoped to the supported subset and require explicit diagnostics for unsupported coroutine bytecode paths.
- **[Risk] Generalizing `Coroutine` can regress the already-green AST coroutine behavior.** → Re-run the existing coroutine library tests plus new bytecode-focused tests as part of the change.

## Migration Plan

1. Add the bytecode continuation model and shared coroutine hooks without changing the stdlib surface.
2. Teach the `lua_bytecode` VM to suspend and resume through those hooks for the supported subset.
3. Add source-engine and upstream-chunk coroutine tests before enabling broader documentation claims.
4. Keep unsupported bytecode coroutine paths explicitly diagnostic until additional opcode families are covered.

Rollback is straightforward: the change is internal to the `lua_bytecode` runtime and coroutine machinery, so the source-engine selection can keep rejecting those paths if the continuation work proves unstable.

## Open Questions

- Should the first slice include yielding across metamethod-triggered bytecode calls, or should that remain explicitly unsupported until the base coroutine subset is stable?
- Do we want a dedicated bytecode continuation type in `lib/src/lua_bytecode/`, or a runtime-neutral continuation interface that the AST path could also adopt later?
