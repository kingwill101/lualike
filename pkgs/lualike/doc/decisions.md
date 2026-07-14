# Design Decisions

This file records non‑obvious design decisions and their rationale so they
aren't rediscovered the hard way.

---

## IR contract: optimize before lowering, lower mechanically, execute thinly

**Date:** 2026‑07‑12  
**Status:** Active

**Context:** The current pipeline already emits IR and then lowers to Lua bytecode, but the exact boundary is easy to blur: some decisions are still made in AST passes, some in IR compilation, and some in bytecode helpers. That makes the VM larger than it should be and makes it unclear where future optimizations belong.

**Decision:** The IR layer is the optimization boundary. All shape decisions that affect runtime cost must be finalized before bytecode lowering. The bytecode lowering step is a mechanical translation of finalized IR into compact executable form, and the VM is only responsible for dispatching those finalized instructions.

**Contract:**
- AST passes may annotate or simplify source, but they must not be the final place where runtime shape is decided.
- SSA and IR passes own value numbering, constant propagation, dead-code elimination, inlining, loop motion, coalescing, and escape analysis.
- Bytecode lowering must not discover new semantics; it should only encode the already-decided IR shape.
- The VM should execute the emitted bytecode without re-inferring call shape, closure shape, or optimization opportunities.

**Implications:**
- New performance work should start in IR/SSA, not in the VM.
- If the VM needs to infer something repeatedly, that decision likely belongs upstream.
- The lowering layer should stay boring and auditable.

---

## Builtin results use transient (non‑cached) primitive Values

**Date:** 2026‑07‑11  
**Status:** Active  
**Context:** The profiled hot spot in the lua‑bytecode VM for a `math.sin(i)`
loop was `Interpreter.constantPrimitiveValue` at ~15 % self time. Each
`math.sin(i)` / `math.cos(i)` call created a permanent cache entry in
`_cachedDoubleValues`, even though the result (a unique `double`) would
never be reused — the cache grew unboundedly with every distinct value.

**Decision:** `BuiltinFunction.primitiveValue()` now uses
`Value.transientPrimitive()` for scalar primitives (numbers, `nil`, `bool`)
instead of `cachedPrimitiveOrValue()` → `Interpreter.constantPrimitiveValue()`.
Non‑scalar results (tables, closures, strings) still take the cached path.

**Rationale:**
- Math functions produce unique floating‑point results; caching them wastes
  memory and CPU on HashMap insertions that never hit.
- Transient primitives have `skipAllocationDebt = true` and
  `skipGcRegistration = true`, so the GC pays zero tracking cost for them.
- Scalar primitives are value‑typed in Lua — identity is irrelevant, so
  sharing the `Value` wrapper provides no correctness benefit.
- The change eliminated the #2 CPU hotspot and reduced heap allocation by
  ~91 % for a 500 K‑iteration math loop.

**Alternatives considered:**
1. *`setPrimitiveRegister` — store raw double in the frame register, skip
   the Value allocation entirely.* Abandoned because it broke `gc.lua`
   memory assertions and `db.lua` debug‑library mutation (the frame‑slot
   interface couldn't distinguish a raw primitive from a Value without
   pervasive type changes).
2. *`isRawPrimitive` flag — mark existing cached Values so GC skips them.*
   This is still in use as a secondary optimisation, but it doesn't avoid
   the cache entry allocation itself.
3. *Modify only the inline‑builtin call path.* Rejected because the Value
   was already created inside `BuiltinFunction.primitiveValue()` before the
   caller could intercept it.

**Benchmark result (compiled AOT, 500 K math‑sin‑cos loop):**

| Metric             | Before  | After   | Δ        |
|--------------------|---------|---------|----------|
| Wall time          | 4.19 s  | 2.15 s  | −48.7 % |
| CPU time           | 5.27 s  | 2.13 s  | −59.5 % |
| Value instances    | 885 K   | 13 K    | −98.5 % |
| Heap delta         | 260 MB  | 23 MB   | −91 %   |

---

## Boxing elimination via `isRawPrimitive` flag (vs. storage‑type change)

**Date:** 2026‑06‑??  
**Status:** Active  

Several attempts to eliminate `Value` boxing for primitives at the
register‑storage level failed. Each broke `gc.lua` memory assertions or
`db.lua` debug‑library mutation:

- `List<Object?>` registers (breaks GC root tracing)
- Parallel array of primitives (breaks GC invariants)
- `HashMap` cache of primitives (breaks `gc.lua` assertion)
- `_primitiveSlots` list (breaks `db.lua` debug‑library mutation)

**Fallback:** The `isRawPrimitive` flag on `LuaValueMetadata` marks
`Value` objects wrapping `int`/`double`/`bool`/`nil` so the GC skips them
in `getReferences()`. This keeps `List<Value>` registers unchanged — GC
roots are intact and the debug library can still autobox — while avoiding
the tracing overhead.

---

## SSA passes enabled by default on bytecode path, off on IR path

**Date:** 2026‑06‑??  
**Status:** Active  

All seven SSA optimisation passes (DCE, GVN, SCCP, LICM, register
coalescing, escape analysis, scalar replacement) run on the lua‑bytecode
pipeline. They are gated off on the IR path because the IR VM cannot
handle post‑SSA instruction patterns.

---

## Optimizer rewrites preserve semantic type, metadata, and control flow

**Date:** 2026-07-13
**Status:** Active

**Context:** The optimized bytecode path passed broad Lua programs while
focused Dart tests still exposed values and metadata that were only
approximately preserved. Integer truthiness hid boolean-to-integer rewrites,
ordinary varargs hid lost named-vararg metadata, and straight-line execution
hid folds that removed branch targets.

**Decision:** An optimization is valid only when it preserves all observable
prototype and control-flow semantics, not merely the common execution result.

**Required invariants:**
- SCCP's integer lattice contains integers only. Booleans are not represented
  as `0` or `1`, and boolean-producing comparisons are not rewritten to
  `LOADI`.
- Every pass that rebuilds a prototype copies semantic metadata, including the
  named-vararg register.
- Peephole destination folding is rejected when the removed `MOVE` has an
  incoming branch or loop edge, or when its source temporary remains live.
- Register analysis models complete implicit windows for numeric and generic
  loops, including loop-carried iterator state.
- LICM does not transform reverse-layout numeric or generic loops until it can
  construct a control-flow-aware preheader without moving the physical loop
  body across its header.

**Rationale:** These rules are intentionally conservative. A missed fold costs
an instruction; an unsound fold silently changes language behavior or produces
malformed control flow.

---

## Forward gotos snapshot close scopes at the jump site

**Date:** 2026-07-13
**Status:** Active

**Context:** A forward `goto` can leave a scope containing `<close>` locals
before its target label is defined. By resolution time, compiler scope stacks
for the exited block have already been popped, so recomputing close state from
the current scope incorrectly removes the required `CLOSE`.

**Decision:** Pending gotos retain the lowest closable register for every
visible lexical scope. Label resolution compares that snapshot with the target
scope and emits `CLOSE` only for scopes crossed by the jump.

**Rationale:** The jump-site snapshot is the only state that accurately
describes resources owned by scopes that may no longer exist when a forward
label is resolved. It also avoids closing resources in an outer scope when the
jump remains inside that scope.

---

## Debug call names use pre-result CALL state

**Date:** 2026-07-13
**Status:** Active

**Context:** After a `CALL` executes, its destination registers may become
named locals. Inferring the callee name from that post-call program counter
made `local ok = pcall(f)` appear as a call to `ok`. This was observable from
`debug.getinfo` inside error-time `<close>` handlers.

**Decision:** Call-site naming resolves active locals at the `CALL`
instruction, before result-local lifetimes begin. Tail-call fast paths preserve
the same inferred name while reusing bytecode frames.

**Rationale:** Debug names describe the called expression, not the variable
that receives its result. Error unwinding removes the failed frame before close
handlers run, matching the reference stack shape.

---

## Manual GC step results are completion signals, not success constants

**Date:** 2026-07-13
**Status:** Active

`collectgarbage("step", size)` returns a boolean indicating whether that
bounded slice completed the current collection cycle. Either value is valid
for one call; tests must assert the boolean result type and test pacing over a
sequence of steps rather than requiring one call to return `true`.

---

## Diagnostic IR output is written to stdout

**Date:** 2026-07-13
**Status:** Active

`--dump-ir` is requested program output and is written to stdout. Stderr is
reserved for diagnostics and failures. CLI integration tests assert this
stream contract.

---

## State restoration only for entry frames / suspended coroutines / debug hooks

**Date:** 2026‑06‑??  
**Status:** Active  

The caller environment and script path are restored only for entry frames,
suspended coroutines, or frames with active debug hooks. Nested frame calls
skip restoration because subsequent frame entry overwrites these values
anyway.

---

## Table inline cache uses `Object.hash` instead of XOR

**Date:** 2026‑06‑??  
**Status:** Active  

The inline‑cache version uses `Object.hash(instructionPc, word.c)` instead
of bitwise XOR to avoid collisions across different `(PC, field)` pairs.
A per‑storage `Expando` with `icVersion` drives invalidation.

---

## Stackless coroutines — reverted

**Date:** 2026‑07‑??  
**Status:** Superseded  

A stackless coroutine implementation compacted the frame on every
yield/resume, but the per‑operation overhead (list copy + new frame
allocation) caused a ~77 % regression on the lua‑bytecode engine. A
correct implementation would need incremental copy‑on‑write or shared
immutable register storage.

---

## IR compiler register allocation: temp-heavy binary expressions

**Date:** 2026‑07‑13  
**Status:** Known inefficiency; accepted for now  

**Context:** The IR compiler's `_emitBinaryExpression` always copies
both operands to temporary registers before computing, even for simple
`local a, b; return a + b`. This produces extra MOVE instructions that
the SSA coalescer can eliminate for straight-line code but not across
loop-carried register redefinitions.

**Impact:** The `06_loops.lua` benchmark (`sum = sum + i`) emits:
```
MOVE tmp1, sum     ; copy left  operand
MOVE tmp2, i       ; copy right operand
ADD  tmp1, tmp1, tmp2
MOVE sum, tmp1     ; copy result back
```
vs luac55's:
```
ADD sum, sum, i
```

A fix would require the binary emitter to read directly from the
source registers when they are simple locals and no intervening write
clobbers them. This is a register-allocation/coalescing improvement
that should be done at the SSA level rather than by special-casing in
the IR compiler.

---

### GC marking sets use identity hashing

**Date:** 2026‑07‑11  
**Status:** Active  

The generational GC's `_queuedToMark`, `_toBeFinalized`, and
`_alreadyFinalized` sets (all `Set<GCObject>`) now use
`HashSet<GCObject>.identity()` instead of the default `HashSet`.

**Rationale:** These sets only track whether a specific object has been
enqueued — identity is the correct comparison, and the expensive
`Value._canonicalNumericHashKey` (string formatting + `BigInt.parse` for
doubles) is unnecessary. The `_rememberedSet` already used identity;
this aligns the remaining GC bookkeeping sets.

**Result:** `_canonicalNumericHashKey` dropped from the #1 profile
hotspot (29 % self-time in math.lua) entirely out of the top 25.

---

### Value hash-code caching

**Date:** 2026‑07‑11  
**Status:** Active  

The Lua-aware hash code (`Value.hashCode → _luaHashCode →
_canonicalNumericHashKey`) is cached in
`LuaValueMetadata._cachedLuaHashCode` after first computation. This
avoids the expensive `BigInt.parse(value.toStringAsFixed(0))` for
doubles on every table lookup or GC marking step.

**Why not always cached?** Values without `LuaValueMetadata` (rare,
simple wrappers without runtime flags) skip the cache and recompute on
every call.

**Result:** Halved `_canonicalNumericHashKey` self-time from 29 % to
16.3 % in math.lua before the GC identity-set change eliminated it
entirely from the top 25.

---

### Deferred call-site name caching

**Date:** 2026‑07‑11  
**Status:** Active  

`_callSiteNameInfo` (called on every CALL instruction) walks backwards through
bytecode instructions to determine the call target's name and source (global,
field, method, local). This is used for informative error messages like
`"attempt to call a nil value (global 'bbbb')"`.

**Optimization:** The result is cached per `(prototype, pc)` in
`LuaBytecodeVm._callSiteNameCache`. Since a call site never moves in the
bytecode, the name is computed once per call site and reused on subsequent
calls.

**Result:** `_callSiteNameInfo`, `_inferRegisterCallNameInfo`, and
`_isEnvironmentRegister` dropped out of the top 25 hotspots entirely.
Combined savings ≈ 21 % total time for math.lua (previously 10.9 % + 10.4 %
total).

---

### Remaining optimization targets (2026‑07‑11)

After all current optimizations, the remaining top‑25 self‑time hotspots in the
math.lua benchmark are fundamental VM operations:

| Rank | Self % | Function | Notes |
|---|---|---|---|
| 1 | 11.1 % | `_executeFrame` | Main loop dispatch |
| 2 | 6.5 % | `LuaBytecodeFrame.register` | Register read |
| 3 | 4.8 % | `LuaBytecodeFrame.setRegister` | Register write (write barrier) |
| 4 | 4.3 % | `rawEquals` | Equality comparison |
| 5 | 2.5 % | `constantPrimitiveValue` | Value wrapping for constants |
| 6 | 2.3 % | `Value.transientPrimitive` | Transient Value creation |
| 7 | 1.7 % | `MetaTable.isDefaultMetatableActive` | Per‑Value metatable check |
| 8 | 1.4 % | `needsSuspendingBoundary` | Per‑instruction yield‑point query |

Further gains would require architectural changes: synchronous instruction
dispatch for the non‑yielding path, register storage that avoids Value boxing
(abandoned — see Boxing elimination above), or re‑implementing equality and
arithmetic with native unboxed types.

---

### TailCallException replaced with `_TailCallResult` return value

**Date:** 2026‑07‑11  
**Status:** Active  

`TailCallException` was thrown as control flow from `_executeFrame` for
every tail call. Because the entire call chain (`invoke` → `_runFrame` →
`_executeFrame`) is async, the exception went through
`_Future._completeErrorObject` — the expensive async error path that
captures stack traces and propagates errors through listeners.

**Fix:** `_executeFrame` now returns `_TailCallResult` (a plain data class
that does not extend `Exception`) on `TAILCALL` instructions. The callers
check with `is _TailCallResult` and re-dispatch normally. The async
completion goes through the normal `_completeWithValue` path.

`TailCallException` is retained as a legacy path for non-closure tail calls
and coroutine-resume paths that still use it.

**Result:**
- calls.lua: 4.50s → 1.42s (−68%)
- math.lua: 2.76s → 2.28s (−17%)
- Combined absolute improvement vs baseline: calls.lua −71%, math.lua −76%

---

## Official bytecode omits local registers; recover on parse

**Date:** 2026‑07‑12  
**Status:** Active  

**Context:** Official Lua chunks store locals as `(name, startPc, endPc)` only.
Our VM debug tables require `register`. Pipeline compile → serialize → load
therefore dropped registers and `debug.getlocal` returned nil after fold.

**Decision:** After parsing a chunk, infer registers with Lua's stack discipline
(`inferLocalRegisters` / `prototypeWithInferredLocalRegisters` in
`lib/src/lua_bytecode/debug_local_caches.dart`): active locals form consecutive
slots, and a local's register is its depth on that stack at birth. Also force
main prototype `lineDefined = 0` on IR→bytecode lowering so main chunks are not
treated as regular Lua functions (which inject a synthetic `(vararg table)`
local for `debug.getlocal`).

**Where this is wired:**
- Parse: `LuaBytecodeReader.readChunk` always runs inference on the main tree.
- Lowering: `lowerIrPrototypeToLuaBytecodePrototype` forces main `lineDefined=0`
  and copies IR local registers/PCs (PCs remapped through the lowerer's pcMap).
- Fold path: `executeCode` with `foldEnabled` uses `CompilePipeline` then
  `loadBytecode(serializedBytes)` — inference is mandatory for that path.

**Related SSA safety fixes (same change set):**
- **Coalesce:** treat CALL/RETURN/CONCAT multi-register windows as reads;
  refuse to coalesce when src and dst both live as distinct call args
  (`ssa_coalesce_pass.dart`).
- **GVN:** invalidate value-number sources when registers are redefined
  (`ssa_gvn_pass.dart`) — otherwise a second `GETTABUP debug` reuses a register
  that CALL already overwrote with a string.
- **DCE:** keep pure stores into named debug-local registers
  (`ssa_dead_code_pass.dart`) so `local a = 10` is not dropped when only
  observed via `debug.getlocal`.
- **SCCP:** only rewrite instructions that themselves fold; never every write
  to a register that once held a constant (`ssa_sccp_pass.dart`).

**Regression tests:**
`test/lua_bytecode/local_register_inference_test.dart`

**Still open:** optional private serialize extension if stack inference is ever
insufficient for non-stack local layouts.

---

## Lua-bytecode always uses the IR+SSA pipeline

**Date:** 2026‑07‑12  
**Status:** Active  

**Context:** `--lua-bytecode` used to lower via the direct AST→bytecode emitter
unless `--fold` was set. That split made debug/register bugs invisible on the
default suite path while optimizations only ran on the fold path.

**Decision:** `EngineMode.luaBytecode` always compiles through
`CompilePipelineConfig.luaBytecodeOptimized` (AST passes + IR + SSA + register
budget check + mechanical lower + serialize). `--compile` and
`LuaBytecodeRuntime.runAst` share that config. The pure IR engine still keeps
SSA off (post-SSA shapes are not IR-VM ready).

**Register budget:** After SSA, `validateIrChunkRegisterBudget` rejects
prototypes that cannot fit in 8-bit ABC fields / u8 maxstack (see
`lib/src/ir/register_budget.dart`).


---

## CALL ABI: pass target register as call base for assignments

**Date:** 2026‑07‑13  
**Status:** Active  

**Context:** The IR compiler's CALL instruction uses the same register for
the function and the first result (`R(A) = function, R(A)..R(A+C-1) = results`).
For `local a, b, c = multi()`, the compiler previously allocated a fresh
register for the call base, then MOVEd results to the named variable
registers — adding 1-3 MOVEs per call.

**Fix:** `_emitAssignmentValues` now passes the first target register
as `baseRegister` to `_emitFunctionCall` when available. The call writes
results directly into the target registers, eliminating the unpacking MOVEs.

**Impact (--raw, instructions vs luac55):**
- calls: 18→15 (+2→-1) now beats luac55
- upvalues: 33→29 (+3→-1) now beats luac55
- multiret: 20→13 (-1→-8) significantly better
- coroutine: 39→38 (-4→-5) better

**SETFIELD Kst inlining (2026‑07‑13):** The `_tryLiteralConstant` helper
checks if a table-constructor value is a literal and, if so, emits
SETFIELD with k=true (value as Kst constant index) instead of emitting
LOADI + SETFIELD with a register value.  This eliminated the last
remaining gaps in `table` and `loops`.

**Remaining:** float (+2) — from `nan ~= nan` not-equal comparison
pattern that emits an extra NOT instruction.

---

## SROA is conservative across table aliases and child captures

**Date:** 2026-07-13
**Status:** Active

**Context:** Scalar replacement rewrites constant-key table accesses through
the register containing `NEWTABLE`. It does not yet maintain an alias set. A
table copied by `MOVE`, or captured from the parent stack by a child prototype,
can therefore be observed through a register that the pass never rewrites.

**Decision:** Do not scalar-replace a table when its allocation register is a
`MOVE` source, appears in a child prototype's in-stack upvalue descriptor, or
is read by `CHECKGLOBAL`. The latter performs a dynamic environment-table
lookup that SROA cannot rewrite. This intentionally gives up an optimization
rather than changing table identity or leaving an observer pointed at a
removed allocation.

**Future work:** Track equivalent table registers and rewrite every alias as a
single scalar object. Until then, the conservative escape rule is mandatory.

**Validation:** `test/ir/ssa_escape_pass_test.dart` covers moved tables, child
captures, and local environment tables consumed by `CHECKGLOBAL`; the
all-engine compatibility suite passes 30/30 for IR and lua-bytecode.

---

## Comparison operands are read-only and polarity is explicit

**Date:** 2026-07-13
**Status:** Active

**Context:** `EQ`, `LT`, and `LE` read both operands before materializing their
boolean result. Re-emitting a local right operand into the left register
destroys one of those inputs. The comparison `k` bit also controls branch
polarity and cannot safely rely on the instruction default.

**Decision:** Read local right operands directly from their binding registers
and evaluate only non-local expressions into temporaries. Emit `k=true` for
normal equality and relational comparisons, and `k=false` for not-equal.
Literal relational instructions follow the same explicit-polarity rule.

**Validation:** Compiler tests assert distinct source registers and polarity;
VM tests execute the same comparison in the IR and optimized lua-bytecode
engine modes.

---

## Late GC tracking reuses Value allocation classification

**Date:** 2026-07-13
**Status:** Active

**Context:** Values can be created with GC registration deferred and later
discovered through the object graph. Reachability tracking and Lua-visible
memory accounting are separate concerns. Charging a transient primitive only
because it was tracked late makes `collectgarbage("count")` depend on discovery
order and broke the weak-table accounting assertion in `gc.lua`.

**Decision:** `Value.shouldCountGcAllocation` is the single classification for
normal and late registration. `ensureTracked()` always assigns a generation,
but records excluded Values with `MemoryCredits.onTrackExcluded()` rather than
charging an allocation.

**Validation:** `test/gc/late_tracked_value_accounting_test.dart` verifies that
late-tracked scalar and transient string Values enter the young generation
without increasing reported memory.

---

## Manual collection calls perform one incremental slice

**Date:** 2026-07-13
**Status:** Active

**Context:** Retrying collection internally and carrying manual-step debt made
small and large `collectgarbage("step", size)` calls converge on completing an
entire cycle in one API call. That removed Lua's observable size-dependent
pacing.

**Decision:** One manual-step call maps to one bounded incremental GC slice.
The requested kilobytes are converted to work units with a fixed scale and a
ceiling; the return value is true only if that slice completes the cycle.
Automatic collection being stopped does not disable explicit manual work.

**Validation:** `test/gc/manual_step_pacing_test.dart` verifies both optimized
engines, requires more than one large step, and requires more small steps than
large steps for the same workload.

---

## `require` returns module and loader data as Lua results

**Date:** 2026-07-13
**Status:** Active

**Context:** Lua 5.4 searchers return a loader plus loader data. `require`
passes both values to the loader and returns the loaded module plus loader data.
A raw Dart list does not model Lua multi-return behavior: single-value contexts
can observe the list itself instead of its first element.

**Decision:** Return `LuaResults([module, loaderData])`. Multi-value assignments
receive both values, while a single-value expression receives only the module.
Normalize string paths before exposing loader data so filesystem searchers keep
stable platform paths.

---

## Final optimization compatibility gate is all green

**Date:** 2026-07-13
**Status:** Active

After the SROA, comparison, GC accounting, manual-step, and `require` fixes,
`./test_runner --all-engines` rebuilt the CLI and passed:

| Engine | Result |
|---|---:|
| AST | 30/30 |
| IR | 30/30 |
| lua-bytecode | 30/30 |

`heavy.lua` was omitted by the runner's default `--skip-heavy` policy. This
90-test compatibility gate is the correctness baseline for subsequent IR and
bytecode optimization work.
