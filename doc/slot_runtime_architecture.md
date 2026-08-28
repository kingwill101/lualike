# Slot-Native Runtime Architecture

## Status

Accepted direction. Migration is incremental and every retained slice must
preserve the upstream Lua `test_runner` suite.

## Problem

The runtime historically used `Value` as all of the following:

- an internal scalar temporary;
- a function argument and result carrier;
- a mutable local binding payload;
- a table, closure, and userdata identity wrapper;
- a metadata carrier for metatables, `<const>`, and `<close>`;
- a public Dart interoperability object.

Likewise, `Environment` acts as global storage, lexical-scope storage, call
frame storage, debugger state, and closure storage. This makes a simple numeric
expression pay for public wrappers, maps, boxes, metadata checks, and custom-GC
bookkeeping even when none of those facilities are observable.

The Relic Breach walking workload makes the cost concrete. One measured
240-frame window created about 83,000 `Value` objects. Allocation traces
attributed most churn to argument normalization, local-binding clones, unary
results, and math builtin results. Pooling function environments and boxes
helped, but pooling can only amortize the old representation; it cannot remove
its conversions or map lookups.

## Decision

Use one slot-native execution contract across AST, IR, and Lua-bytecode paths.

### Result contract

- One Lua result is a `LuaSlot`.
- Zero results are an empty `LuaResults` when arity is observable, or `null`
  only at an explicitly adjusted single-result boundary.
- Multiple results are `LuaResults`.
- Plain Dart `List` is not an internal result carrier.
- A `Value` is materialized only when Lua-visible metadata or a public API
  requires the facade.

The distinction between zero results and one `nil` result must remain explicit
until the caller applies Lua result-adjustment rules.

### Slot contract

A `LuaSlot` may contain:

- raw `nil`, booleans, numbers, and internal string values;
- identity-bearing runtime objects such as tables, closures, threads, and
  userdata;
- a `Value` only when per-value metadata or a public mutable facade is
  observable;
- a `LuaResults` only at result boundaries, never as an ordinary scalar slot.

Slot consumers use `rawLuaSlot` and slot-aware operations. They do not call
`Value.unwrap()` merely to recover a primitive that the producer already had.

### Frame contract

Ordinary function parameters, locals, and expression temporaries live in a
fixed indexed slot array described by an immutable function layout. The layout
is computed once before execution and contains:

- parameter and local slot indices;
- lexical lifetime ranges;
- captured-local and `<close>` flags;
- upvalue descriptors;
- debug names and source ranges;
- maximum temporary-slot demand;
- fixed builtin call arity where known.

Execution must not rediscover closure shape, local indices, or call shape on
every invocation. This follows the existing rule that optimization decisions
belong before runtime dispatch.

During the incremental AST migration, every populated slot also records the
lexical `Environment` that owns the binding. A cached slot is valid only while
that owner is the active environment or one of its parents. Per-name slot
stacks resolve shadowing from innermost to outermost visible owner. This avoids
letting a slot populated inside a `do`, branch, or loop remain visible after
that scope exits, without rebuilding name maps or clearing declaration caches
at every block boundary.

### Capture contract

An uncaptured local is an ordinary frame slot and has no `Box`. Capturing the
local promotes that slot to a shared upvalue cell. The cell reads from the open
frame until the defining scope closes, then retains the slot payload directly.

`debug.upvaluejoin` changes cell identity, not merely the current payload.
`<const>` and `<close>` belong to slot/cell binding metadata rather than being
inferred from whatever `Value` happens to occupy the binding.

### Environment contract

`Environment` remains the compatibility and dynamic-namespace structure for:

- globals and `_ENV`;
- `load` with a supplied environment;
- host embedding APIs;
- debugger materialization;
- legacy AST frames not yet migrated.

An ordinary migrated function call does not allocate an `Environment` or a map
for its lexical locals. Debug APIs receive a lazily materialized environment
view backed by the live frame slots.

### Builtin contract

Builtins use slot-native fixed-arity entry points where their shape is known.
Those entry points receive existing Lua slots and return a raw `LuaSlot` or
`LuaResults`. The generic compatibility entry point remains available for
variable arity, asynchronous host operations, and external Dart subclasses.

Skipping a managed Lua call frame and using slot-native arguments/results are
separate capabilities. Debug hooks restore an observable managed frame even
when a builtin has a fixed-arity implementation.

### Suspension contract

The common evaluator and VM path is synchronous. A `Future` is created only
when execution reaches an operation that can actually suspend:

- coroutine yield/resume;
- an asynchronous host builtin;
- yielding metamethods;
- asynchronous filesystem or platform services.

Suspension snapshots the indexed frame and its open upvalue cells. Synchronous
expressions must not allocate a `Future` merely because a distant operation
might suspend.

### Public boundary

Public APIs continue to expose `Value` where compatibility requires it. One
central adapter materializes a facade from a slot, preserving canonical table
identity, metatables, debug mutation, and GC reachability. Public callers are
never required to understand raw internal slots.

## Migration

1. Normalize builtin results and arguments to `LuaSlot`/`LuaResults` while
   preserving the generic `Value` facade entry point.
2. Introduce a shared indexed frame and upvalue-cell interface, initially
   alongside existing `Environment` frames.
3. Generate immutable function layouts in the compiler/analysis boundary.
4. Move closure-free function parameters and locals to indexed slots.
5. Add lazy upvalue promotion and migrate captured locals.
6. Materialize debugger environments and `Value` facades on demand.
7. Route the source-engine default through the slot-native compiled path only
   after it beats the AST path and passes parity gates.
8. Remove legacy map/box execution paths after no supported engine depends on
   them.

Each step must be independently reversible while the migration is incomplete.
Feature flags are measurement controls, not permanent alternate semantics.

### Current incremental coverage

The AST compatibility engine currently has an indexed frame with Box-backed
slots as its general path. It stores bindings directly in these proven cases:

- non-`_ENV` parameters in closure-free functions;
- ordinary uncaptured locals in closure-free functions, including primitive
  and identity-bearing values in nested
  block, branch, and loop-body declarations whose lexical owner is visible;
- non-`_ENV` parameters and ordinary uncaptured locals in closure-capable
  functions when
  a conservative nested-function scan proves that their names never occur
  below a nested function boundary.

These frames remain authoritative across ordinary Lua/host calls, tail-call
rebinding, coroutine yield/resume, and protected calls. The logical
`CallFrame.engineFrameState` owns the indexed frame; `pcall` and `xpcall`
restore the caller's environment, function, and engine frame as one execution
tuple. This is required when a stack-limit error occurs before a callee can
install and later unwind its own function-body state.

Debugger enumeration also comes from the indexed frame. Its declaration-slot
view contains both direct and Box-backed locals in one stable order, so mixed
storage cannot reorder locals and a direct nested-block binding remains visible
without a synthetic Environment entry. Failed `assert` calls retain a managed
call-site frame for source attribution; successful assertions may still use the
leaf builtin fast path.

`_ENV`, `_G`, attributed locals, potential captures, and declarations made
while a debug hook is active retain their Environment/Box representation. The
nested-function scan intentionally accepts false positives: an identifier
declared inside a nested function may unnecessarily keep an outer name boxed,
but a possible capture is never moved into a direct slot. An uncaptured table,
string, function, or userdata keeps its canonical `Value` facade directly in
the slot; call-frame GC roots and the declaration-ordered debugger view preserve
reachability and identity without a Box. Empty parser attributes are normalized
to the absence of an attribute before ordinary local binding; this prevents a
synthetic empty string from forcing primitive `Value` clones.

The compile-time measurement controls are
`LUALIKE_AST_SLOT_ONLY_PARAMETERS`, `LUALIKE_AST_SLOT_ONLY_LOCALS`, and
`LUALIKE_NORMALIZE_EMPTY_LOCAL_ATTRIBUTES`. The nested-declaration expansion
has its own attribution control, `LUALIKE_AST_SLOT_ONLY_NESTED_LOCALS`, which
leaves the top-level direct-local path enabled when false.
`LUALIKE_AST_SLOT_ONLY_CALL_CAPABLE_FRAMES` restores the prior leaf-only
eligibility boundary when false.
`LUALIKE_AST_SLOT_ONLY_UNCAPTURED_CLOSURE_BINDINGS` restores the previous
all-boxed boundary for closure-capable functions when false. All default to the
retained path. `LUALIKE_AST_SLOT_ONLY_IDENTITY_LOCALS` independently restores
Box-backed storage for identity-bearing local values while leaving primitive
direct slots enabled.

## Correctness gates

Every retained migration slice must pass:

- focused tests for the changed contract;
- the complete Dart package test suite;
- the compiled upstream Lua `test_runner` suite;
- debug local/upvalue mutation tests;
- closure, coroutine, `<const>`, `<close>`, weak-table, and GC tests;
- differential behavior checks against the installed reference Lua CLI when
  semantics are uncertain.

The direct identity-local slice passed this gate after the first upstream run
caught and drove a repair for stripped-chunk debugger ordering: the complete
Dart package suite exited successfully, followed by 30/30 AST, 30/30 IR, and
30/30 lua-bytecode cases in a freshly compiled standalone runner.

The final source-engine switch additionally requires the same LOVE project to
run through native LOVE and lualike with matching input, world reset, logical
resolution, and captured frame state.

## Performance gates

Allocation reduction alone is insufficient. Retain a slice only when it does
not introduce a repeatable regression in the real walking workload.

Record at least five deterministic 240-frame profile windows per side, then a
reverse-order leg for borderline results. Compare:

- exact `Value`, `Box`, and frame/cell construction counters;
- update p95 and p99;
- CPU-frame p95 and p99;
- maximum CPU-frame time and over-budget frame counts;
- command count, fallback count, and presentation geometry;
- synchronized Canvas/GPU/native visual captures.

VM allocation-profile accumulators are supporting evidence only after their
monotonicity is validated for the active runtime. Exact owned-class counters
and allocation traces remain authoritative when service counters are not
monotonic.

## Non-goals

- Removing `Value` from public Dart APIs.
- Making every table or closure a raw Dart collection/function.
- Maintaining separate AST and bytecode semantic implementations forever.
- Trading Lua debug, closure, GC, or close semantics for benchmark speed.
- Treating average FPS as proof that stutter improved.
