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

**Still open:** full `locals.lua` / `db.lua` under fold; 8-bit register budget
for SSA temps; optional private serialize extension if stack inference is ever
insufficient.

