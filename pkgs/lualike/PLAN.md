# Lualike Optimization Priorities

Based on architecture analysis, LuaJIT/Lua 5.4 research, and current codebase state.

---

## Tier 1: Quick Wins

These are low-risk, high-impact optimizations that require no architectural changes and directly reduce instruction count or eliminate redundant work in the hot loop.

### 1.1 Peephole: Merge Consecutive LOADNILs → Single LOADNIL with Count

**Current state:** The bytecode emitter already packs `LOADNIL r, n-1` but the IR peephole and bytecode peephole don't merge adjacent `LOADNIL r; LOADNIL r+1` sequences. The VM's `LOADNIL` handler already loops (`for (var index = 0; index <= word.b; index++)`), so a single `LOADNIL r, 3` replaces four separate loads.

**Impact:** Common in destructuring and multi-return scenarios. Every `local a, b, c` at scope entry emits multiple LOADNILs for unset slots.

**Complexity:** ~40 lines in each peephole pass. Pattern: scan for consecutive `LOADNIL a, 0` → `LOADNIL a+k, 0` where registers are contiguous, merge into `LOADNIL a, k`.

**Risk:** Minimal — purely mechanical pattern match.

### 1.2 Peephole: Load-Store Forwarding Within Basic Blocks

**Current state:** Neither peephole pass performs any forwarding. After `LOADK r, k`, if `r` is never written before the next read, the load is redundant. Similarly `SETFIELD t, k, v; GETFIELD r, t, k` can forward `v` to `r` if `t` has no side-effecting metamethods.

**Impact:** Eliminates redundant register loads after constant propagation or copy propagation. The `const_propagation_pass.dart` already propagates at the AST level, but the IR/bytecode emitter re-introduces loads. Forwarding at the bytecode level catches these.

**Complexity:** ~100 lines. Requires tracking last write PC per register within a basic block (already partially done for `expireDeadLocals`). Pattern: `LOADK r, k; ...; GETFIELD x, r, k` → skip the load if no intervening write to `r`.

**Risk:** Low — must verify no intervening side effects (table __index metamethods). For LOADK targets with no metamethods, this is safe.

### 1.3 Peephole: Algebraic Simplification (Strength Reduction)

**Current state:** The constant folding pass handles compile-time folding but no peephole patterns exist for runtime-strength reduction.

**Patterns to add:**

| Pattern | Replacement | Notes |
|---------|-------------|-------|
| `ADD r, x, 0` | `MOVE r, x` | Identity |
| `SUB r, x, 0` | `MOVE r, x` | Identity |
| `MUL r, x, 1` | `MOVE r, x` | Identity |
| `MUL r, x, 2` | `ADD r, x, x` | Cheaper than multiply |
| `MUL r, x, 0` | `LOADNIL r` | Annihilation |
| `DIV r, x, 1` | `MOVE r, x` | Identity |
| `IDIV r, x, 1` | `MOVE r, x` | Identity |
| `POW r, x, 0` | `LOADI r, 1` | x^0 = 1 |
| `POW r, x, 1` | `MOVE r, x` | x^1 = x |
| `EQ r, x, x` | `LOADTRUE r` | Reflexivity (when x not NaN) |
| `EQ r, nil, nil` | `LOADTRUE r` | nil == nil is true |
| `EQ r, true, true` | `LOADTRUE r` | Boolean reflexivity |
| `EQ r, false, false` | `LOADTRUE r` | Boolean reflexivity |

**Impact:** Eliminates arithmetic ops when one operand is an identity element. Common in generated code (e.g., `x + 0` from constant propagation leaving a zero).

**Complexity:** ~80 lines. Simple pattern matching on opcode + constant operand detection.

**Risk:** Minimal — must verify operand B or C is a constant (LOADI with value 0, 1, etc.) and that no metamethod is attached.

### 1.4 Peephole: Jump Threading and Empty Branch Elimination

**Current state:** The peephole passes remove `JMP 0` but don't thread jumps or eliminate empty branches.

**Patterns:**

| Pattern | Replacement |
|---------|-------------|
| `JMP +1; <dead code>` | Remove JMP (fall-through is next instruction) |
| `TEST r, 0; JMP +N` (always taken) | `JMP +N` |
| `TEST r, 1; JMP +N` (never taken) | Remove both |
| `JMP +N; ...; JMP +M` where target of first is second JMP | Thread first JMP to final target |
| Empty `if/else` blocks | Remove entirely |

**Impact:** Reduces branch instructions, improving I-cache and branch prediction. Common after constant folding eliminates branch conditions.

**Complexity:** ~60 lines. Requires scanning for JMP targets and checking if intermediate instructions are dead.

**Risk:** Low — must preserve side effects of instructions between jumps.

### 1.5 Value Boxing Elimination: Inline Primitives in Registers

**Current state:** Every register write calls `framePrimitiveValue(runtime, value)` or `runtimeValue(runtime, value)` which wraps primitives in `Value` objects. The VM's hot loop allocates `Value` wrappers for every `LOADI`, `LOADK`, `LOADNIL`, etc.

**Impact:** This is the single largest allocation pressure in the hot loop. For a tight arithmetic loop like `for i = 1, 1000000 do s = s + i end`, every iteration allocates multiple `Value` wrappers.

**Approach:** Use Dart's `Object?` slot type to store raw primitives directly in registers. The `LuaSlot` system already supports this (`rawLuaSlot()` / `isLuaPrimitiveSlot()`), but the bytecode VM doesn't use it for register access. Instead of `frame.setRegister(word.a, framePrimitiveValue(runtime, word.sBx))`, directly store `word.sBx` as `int` in the register slot.

**Complexity:** ~200 lines. Requires changing the register access methods to accept raw primitives and only boxing when needed (e.g., when passing to external functions or storing in tables).

**Risk:** Medium — must audit all register read sites to handle raw primitives. The `LuaSlot` system already provides the primitive detection, so this is about making the VM use it consistently.

---

## Tier 2: Medium-Term

These require more infrastructure but deliver substantial performance gains.

### 2.1 Integer-Only Fast Path for Arithmetic

**Current state:** The VM checks `is num` then dispatches to `vm_arithmetic.dart` which handles both `int` and `double`. There's no specialized integer-only path.

**Impact:** Lua 5.4 introduced integer/number distinction. Most loop counters and array indices are integers. An integer-only fast path avoids `double` boxing, NaN checks, and type promotion.

**Approach:** Add `ADD_I`, `SUB_I`, `MUL_I`, `DIV_I` opcodes (like LuaJIT's `ADDVN` with int constant). The emitter detects when both operands are provably integers (via `LOADI` or integer constant) and emits the specialized opcode. The VM handler does a raw `int` + `int` → `int` without any type checks.

**Complexity:** ~150 lines. New opcodes, emitter changes, VM handlers. The infrastructure (ABC format, opcode table) already supports this pattern — `ADDI`/`SUBI`/`MULI` already exist in some form.

**Risk:** Medium — must verify integer overflow behavior matches Lua 5.4 semantics (automatic BigInt promotion). Can detect overflow and fall back to general path.

### 2.2 Type Specialization in the Compiler

**Current state:** The `TypeNarrowingPass` tracks types through `type()` checks but doesn't propagate this to bytecode emission. The emitter always emits generic opcodes.

**Impact:** If a register is known to hold an integer (e.g., from a loop counter or `type(x) == "number"` check), specialized opcodes can skip type checks entirely.

**Approach:** 
1. Extend the type narrowing pass to track which registers hold integers vs floats vs strings.
2. Add register type annotations to the IR/bytecode prototypes (already partially exists: `registerConstFlags`).
3. The emitter uses these annotations to select specialized opcodes.

**Complexity:** ~300 lines. Requires extending type tracking across the full pipeline.

**Risk:** Medium — type inference must be sound (conservative on unknown). Incorrect specialization would cause runtime type errors.

### 2.3 Table Fast Path: Inline Cache for Known Shapes

**Current state:** `GETFIELD`/`SETFIELD` call `_tryFastTableGetStringKey` which checks the raw table storage but falls back to metamethod calls. No caching of lookup results.

**Impact:** Table access is the most common operation after arithmetic. Inline caching (IC) records the metatable ID and hash/array offset, allowing subsequent accesses to skip the hash lookup.

**Approach:** Cache the last lookup result per (table metatable ID, field name) pair. On subsequent access, check if the table's metatable matches the cache, and if so, use the cached offset directly.

**Complexity:** ~150 lines. Requires adding a small cache structure (8-16 entries) to the VM state, keyed by metatable ID + field name hash.

**Risk:** Low — IC is a standard VM optimization with well-understood correctness properties. Cache miss falls back to normal path.

### 2.4 Function Inlining at Bytecode Level

**Current state:** The `ConstantFoldingPass` inlines functions when all arguments are compile-time constants. The `InliningHeuristicsPass` controls body size limits. But no bytecode-level inlining exists.

**Impact:** Small, frequently-called functions (e.g., getter/setter helpers, utility wrappers) benefit from eliminating call overhead (frame creation, argument marshaling, return).

**Approach:** After type specialization, detect small functions (< ~10 instructions) called with known-integer arguments. Emit the function body inline with the caller's registers, using `LOADI` for the arguments instead of CALL/RETURN.

**Complexity:** ~400 lines. Requires function size analysis, register allocation for inlined body, and control flow integration.

**Risk:** High — must handle upvalues correctly, preserve debugging semantics, and avoid code bloat. Only inline when profiling shows the function is hot.

### 2.5 Dead Store Elimination at Bytecode Level

**Current state:** `DeadCodeEliminationPass` operates at the AST level and only removes unused module exports. No bytecode-level dead store elimination exists.

**Impact:** After constant propagation, many registers are written but never read (the AST pass replaces them with literals, but the emitter still generates the stores).

**Approach:** Track which registers are read before being re-written. Remove STORE instructions where the register is never read before the next write or function return.

**Complexity:** ~120 lines. Requires liveness analysis within basic blocks (extend the existing `expireDeadLocals` infrastructure).

**Risk:** Low — must preserve side effects (table stores, function calls). Only eliminate pure register stores.

---

## Tier 3: Long-Term Architectural

These are fundamental architectural changes that enable the highest performance ceiling.

### 3.1 SSA-Based IR with Optimization Framework

**Current state:** The IR uses a flat instruction list with mutable register slots. No SSA form, no dominance information, no phi nodes.

**Impact:** SSA enables a rich set of optimizations:
- **Global Value Numbering (GVN):** Eliminates redundant computations across basic blocks
- **Sparse Conditional Constant Propagation (SCCP):** More powerful than the current AST-level folding
- **Register coalescing:** Eliminates MOVE instructions by assigning the same physical register to source and destination
- **Instruction scheduling:** Reorder independent instructions for better ILP

**Approach:** Redesign the IR to use SSA form:
1. Basic blocks with explicit predecessors/successors
2. Phi nodes at merge points
3. Dominance tree computation
4. Def-use chains for efficient liveness analysis

**Complexity:** ~2000 lines. Complete IR redesign, new compiler infrastructure, new optimization passes.

**Risk:** High — massive architectural change. Must maintain compatibility with existing bytecode emission and the dual VM model.

**Dependencies:** None, but blocks many other optimizations.

### 3.2 JIT Compilation for Hot Loops

**Current state:** No JIT compilation exists. All code runs through the interpreter.

**Impact:** JIT can achieve 10-100x speedup for tight loops by emitting native machine code. LuaJIT achieves this for Lua code.

**Approach:** 
1. Profile-guided: instrument the interpreter to identify hot loops (count back-edges)
2. Compile hot loops to IR with type specialization
3. Lower IR to native code via Dart's FFI or a custom code generator
4. Deoptimize on type mismatch or side exits

**Complexity:** ~5000+ lines. Requires type profiling, IR-to-native compilation, deoptimization infrastructure, and GC integration.

**Risk:** Very high — native code generation is complex, debugging is difficult, and correctness is hard to verify.

**Dependencies:** SSA IR (3.1), type specialization (2.2), inline caches (2.3).

### 3.3 Generational GC with Write Barriers

**Current state:** Mark-and-sweep with generational collection support (the infrastructure exists in `GCGenerationSpace`). But the VM doesn't use write barriers to track old-to-young pointers.

**Impact:** Generational GC reduces collection pause times by only scanning the nursery for young objects. Write barriers enable this by tracking references from old to young generation.

**Approach:** 
1. Add write barriers to all table store operations
2. Track old-to-young pointers in a remembered set
3. Only scan the remembered set during minor collections

**Complexity:** ~500 lines. The GC infrastructure already supports generations; this adds the VM-level write barrier integration.

**Risk:** Medium — write barriers add overhead to every store but reduce total GC time. Must measure to verify net positive.

### 3.4 Coroutine-Aware Scheduling and Stackless VM

**Current state:** Coroutines are implemented via full stack frames (each coroutine has its own `LuaBytecodeFrame`). Suspension preserves the entire frame state.

**Impact:** Stackless coroutines (like Lua 5.4's implementation) eliminate frame allocation overhead and enable thousands of concurrent coroutines.

**Approach:** Convert to a continuation-passing style where coroutine state is stored in a compact structure rather than a full frame. This requires significant VM restructuring.

**Complexity:** ~1500 lines. Fundamental change to coroutine implementation.

**Risk:** High — breaks the existing coroutine model and requires extensive testing.

### 3.5 SSA IR: Advanced Optimizations

With the SSA framework in place, enable these advanced passes:

| Pass | Impact | Complexity |
|------|--------|------------|
| **GVN (Global Value Numbering)** | Eliminates redundant computations across blocks | ~300 lines |
| **SCCP (Sparse Conditional Constant Propagation)** | More precise constant propagation than AST-level | ~400 lines |
| **Loop Invariant Code Motion (LICM)** | Hoists loop-invariant computations out of loops | ~250 lines |
| **Scalar Replacement of Aggregates** | Eliminates table allocations for known-structure tables | ~200 lines |
| **Escape Analysis** | Determines if objects escape the current scope | ~300 lines |
| **Register Coalescing** | Eliminates MOVE instructions via register assignment | ~200 lines |

**Total:** ~1650 lines across 6 passes. Each is independent and can be implemented incrementally.

---

## Implementation Roadmap

### Phase 1: Quick Wins
1. Peephole: Merge consecutive LOADNILs (1.1)
2. Peephole: Algebraic simplification (1.3)
3. Peephole: Jump threading (1.4)
4. Peephole: Load-store forwarding (1.2)

**Estimated impact:** 5-15% instruction count reduction in typical Lua code.

### Phase 2: Medium-Term
5. Value boxing elimination (1.5)
6. Integer-only fast path (2.1)
7. Table inline caches (2.3)
8. Dead store elimination (2.5)

**Estimated impact:** 2-5x speedup for compute-bound code, 20-40% for table-heavy code.

### Phase 3: Architectural
9. SSA IR framework (3.1)
10. Type specialization (2.2) + advanced SSA optimizations (3.5)
11. Function inlining (2.4)
12. Generational GC write barriers (3.3)

**Estimated impact:** 5-20x speedup for optimized code paths, approaching LuaJIT performance for integer-heavy workloads.

### Phase 4: Frontier
13. JIT compilation (3.2)
14. Stackless coroutines (3.4)

**Estimated impact:** 50-100x speedup for tight loops, full LuaJIT parity.

---

## Key Metrics to Track

| Metric | Current Baseline | Phase 1 Target | Phase 2 Target | Phase 3 Target |
|--------|------------------|----------------|----------------|----------------|
| Instructions per Lua statement | ~5-8 | ~4-6 | ~3-4 | ~1-2 |
| Allocations per arithmetic op | 1-2 Value wrappers | 1 | 0 (raw ints) | 0 |
| Table lookup time (ns) | ~200-500 | ~200-500 | ~50-100 (IC) | ~10-20 (JIT) |
| GC pause time (ms) | Varies | Varies | -50% (DSE) | -90% (generational) |
| Test suite runtime (s) | [baseline] | -5-10% | -30-50% | -70-90% |

---

## Risk Matrix

| Optimization | Correctness Risk | Performance Risk | Maintenance Risk |
|-------------|------------------|------------------|------------------|
| Peephole patterns (1.x) | Very Low | Low | Low |
| Value boxing (1.5) | Low-Medium | Low | Medium |
| Integer fast path (2.1) | Medium | Low | Low |
| Type specialization (2.2) | Medium | Low | Medium |
| Table IC (2.3) | Low | Low | Low |
| SSA IR (3.1) | High | Low | High |
| JIT (3.2) | Very High | Low | Very High |
| GC write barriers (3.3) | Medium | Low | Low |

---

## Decision Points

1. **After Phase 1:** Profile actual workloads. If arithmetic is the bottleneck, prioritize 2.1 (integer fast path). If table access is the bottleneck, prioritize 2.3 (IC).

2. **After Phase 2:** If integer-heavy workloads (e.g., numerical algorithms) are the primary use case, invest in SSA + JIT. If general Lua compatibility is the priority, focus on GC and coroutine optimizations.

3. **SSA vs JIT decision:** SSA alone gives 2-5x improvement without native code. JIT gives 10-100x but with 5x more implementation effort. Consider shipping SSA first and JIT as a future optional enhancement.
