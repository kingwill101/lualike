# Lualike Bytecode Optimization — Implementation Roadmap

> **Generated from PLAN.md architecture analysis.**
> Current date: 2026-07-11
> Codebase state: Dual VM (IR interpreter + Lua 5.5 bytecode VM), no SSA, no JIT.

---

## Table of Contents

1. [Phase 1: Quick Wins](#phase-1-quick-wins)
2. [Phase 2: Medium-Term](#phase-2-medium-term)
3. [Phase 3: SSA IR Foundation](#phase-3-ssa-ir-foundation)
4. [Phase 4: Advanced Optimizations](#phase-4-advanced-optimizations)
5. [Metrics & Benchmarks](#metrics--benchmarks)
6. [Reference Sources](#reference-sources)

---

## Phase 1: Quick Wins

**Goal:** Reduce instruction count by 5–15% with zero architectural changes.
**Risk:** Minimal. All changes are mechanical peephole patterns.

### 1.1 Merge Consecutive LOADNILs

**What:** The bytecode emitter already encodes `LOADNIL r, n-1` when initializing
contiguous registers, but the IR peephole and bytecode peephole don't merge
adjacent sequences emitted by the compiler for multi-return destructuring or
multi-local declarations.

**File targets:**
- `lib/src/ir/peephole_pass.dart` — add pattern to `_peephole()`
- `lib/src/lua_bytecode/peephole_pass.dart` — add pattern to `_peephole()`

**Pattern to match:**
```
LOADNIL r, 0        // b=0 means 1 register
LOADNIL r+1, 0
LOADNIL r+2, 0
→  LOADNIL r, 2     // b=2 means 3 registers (r, r+1, r+2)
```

**Implementation (~40 lines):**
```dart
// In _peephole(), after the existing patterns:
// Merge consecutive LOADNILs into a single LOADNIL with count
if (_isLoadNil(inst) && next != null && _isLoadNil(next)) {
  final instA = _extractA(inst);
  final nextA = _extractA(next);
  final instB = _extractB(inst);  // count - 1
  if (nextA == instA + instB + 1) {
    // Adjacent: merge into LOADNIL instA, instB + nextB + 1
    result[i] = inst.withB(instB + _extractB(next) + 1);
    result.removeAt(i + 1);
    changed = true;
    continue;
  }
}
```

**Test case:**
```lua
-- test/multi_local_init.lua
local a, b, c, d = nil, nil, nil, nil
print(a, b, c, d)  -- nil nil nil nil
-- Expected: single LOADNIL with b=3, not four LOADNILs
```

**Verification:**
```bash
dart run bin/main.dart --ast -e "local a,b,c,d = nil,nil,nil,nil"
# Inspect bytecode output for single LOADNIL instruction
```

**Risk:** Very Low — purely mechanical pattern match, VM already handles the count encoding.

---

### 1.2 Algebraic Simplification (Strength Reduction)

**What:** Eliminate identity operations when one operand is a constant identity
element. The constant folding pass handles compile-time values, but peephole
patterns catch runtime-emitted identity operations (e.g., from partially-folded
code or optimizer-introduced temporaries).

**File target:** `lib/src/ir/peephole_pass.dart`

**Patterns to add (~80 lines):**

| Opcode | Condition | Replacement | Reason |
|--------|-----------|-------------|--------|
| `ADD r, x, 0` | C is LOADI 0 | `MOVE r, x` | x + 0 = x |
| `SUB r, x, 0` | C is LOADI 0 | `MOVE r, x` | x - 0 = x |
| `MUL r, x, 1` | C is LOADI 1 | `MOVE r, x` | x × 1 = x |
| `MUL r, x, 2` | C is LOADI 2 | `ADD r, x, x` | x × 2 = x + x (cheaper) |
| `MUL r, x, 0` | C is LOADI 0 | `LOADNIL r` | x × 0 = 0 → nil in Lua |
| `DIV r, x, 1` | C is LOADI 1 | `MOVE r, x` | x ÷ 1 = x |
| `IDIV r, x, 1` | C is LOADI 1 | `MOVE r, x` | x // 1 = x |
| `POW r, x, 0` | C is LOADI 0 | `LOADI r, 1` | x⁰ = 1 |
| `POW r, x, 1` | C is LOADI 1 | `MOVE r, x` | x¹ = x |
| `EQ r, x, x` | B == C register | `LOADTRUE r` | Reflexivity (non-NaN) |
| `EQ r, nil, nil` | Both are LOADNIL | `LOADTRUE r` | nil == nil |
| `EQ r, true, true` | Both LOADTRUE | `LOADTRUE r` | Boolean reflexivity |
| `EQ r, false, false` | Both LOADFALSE | `LOADTRUE r` | Boolean reflexivity |

**Safety guard:** Must verify no metamethod is attached. For numeric operands
detected via LOADI/LOADF/LOADK (where the constant is a num), metamethods
don't apply. The emitter already uses `ADDI`, `ADDK` etc. for the no-metamethod
path, so we can safely optimize when the opcode is the `K`/`I` variant.

**Test case:**
```lua
-- test/algebraic_simplification.lua
local x = 5
local a = x + 0
local b = x * 1
local c = x ^ 0
local d = x * 2
print(a, b, c, d)  -- 5 5 1 10
-- Expected: +0, *1, ^0 eliminated; *2 replaced with ADD
```

**Risk:** Minimal — pattern match + operand constant check. Must avoid optimizing
NaN-producing operations (e.g., `0/0` identity is NaN, not a simplification).

---

### 1.3 Jump Threading & Empty Branch Elimination

**What:** Reduce branch overhead by threading jumps through intermediate targets
and eliminating branches that are always-taken or never-taken after constant
folding.

**File targets:**
- `lib/src/ir/peephole_pass.dart`
- `lib/src/lua_bytecode/peephole_pass.dart`

**Patterns (~60 lines):**

| Pattern | Replacement | When |
|---------|-------------|------|
| `JMP +1; <dead>` | Remove JMP | Fall-through is next instruction |
| `TEST r, 0; JMP +N` | `JMP +N` | Condition is always truthy (after folding) |
| `TEST r, 1; JMP +N` | Remove both | Condition is never truthy |
| `JMP +N; ...; JMP +M` | Thread first JMP to final target | First JMP target is second JMP |
| Empty `if/else` | Remove entirely | Branch body is empty |

**Implementation approach:**
```dart
// In the peephole loop, build a jump target map first:
final jumpTargets = <int, int>{};
for (var i = 0; i < code.length; i++) {
  if (code[i] is AsJInstruction && code[i].opcode == opcode.jmp) {
    jumpTargets[i] = i + 1 + (code[i] as AsJInstruction).sJ;
  }
}

// Then thread: if JMP target is another JMP, redirect
if (inst.opcode == opcode.jmp && jumpTargets.containsKey(targetPc)) {
  final finalTarget = jumpTargets[targetPc]!;
  result[i] = inst.withSJumpOffset(finalTarget - i - 1);
  changed = true;
}
```

**Test case:**
```lua
-- test/jump_threading.lua
local x = true
if x then
  print("taken")
else
  -- empty branch, should be eliminated
end
-- Expected: empty else branch removed, TEST + JMP optimized
```

**Risk:** Low — must preserve side effects in the dead-code region. Only remove
code that's provably unreachable after constant folding (TEST with a constant
condition).

---

### 1.4 Load-Store Forwarding Within Basic Blocks

**What:** After constant propagation or copy propagation, the emitter re-introduces
redundant loads. Forwarding at the bytecode level catches these by tracking the
last write PC per register within a basic block.

**File target:** `lib/src/ir/peephole_pass.dart`

**Pattern (~100 lines):**
```
LOADK r, k; ...; GETFIELD x, r, k'  →  forward if r is not written between
MOVE r1, r2; ...; ADD x, r1, y      →  replace r1 read with r2
```

**Implementation approach:**
```dart
// Track last write PC per register
final lastWritePc = <int, int>{};
for (var i = 0; i < code.length; i++) {
  final inst = code[i];
  if (_isLoad(inst)) {
    final targetReg = _loadReg(inst);
    // Check if anyone reads this register before the next write
    final nextWrite = lastWritePc[targetReg];
    if (nextWrite != null && nextWrite > i) {
      // The load is redundant — remove it
    }
  }
  if (_isStore(inst)) {
    lastWritePc[_storeReg(inst)] = i;
  }
}
```

**Safety:** Must verify no intervening side effects (table __index metamethods).
For LOADK targets with no metamethods (constants), this is safe. For MOVE
forwarding, must verify source register is not modified.

**Test case:**
```lua
-- test/load_store_forwarding.lua
local t = {x = 10}
local a = t.x  -- LOADK for t, GETFIELD
local b = a + 1  -- should forward 'a' as integer constant if a is const
print(b)  -- 11
```

**Risk:** Low — only forward within basic blocks, no cross-block analysis.

---

### 1.5 Value Boxing Elimination (Highest ROI Quick Win)

**What:** Every register write currently calls `framePrimitiveValue(runtime, value)`
or `runtimeValue(runtime, value)` which wraps primitives in `Value` objects.
The `LuaSlot` system already supports raw primitives via `rawLuaSlot()` /
`isLuaPrimitiveSlot()`, but the bytecode VM doesn't leverage this for register
access.

**Current hot path (from `vm.dart` line ~487):**
```dart
case Opcode.loadI:
  frame.setRegister(word.a, framePrimitiveValue(runtime, word.sBx));
  //  ↑ allocates a Value wrapper for every integer load
  break;
```

**Target hot path:**
```dart
case Opcode.loadI:
  frame.setRawRegister(word.a, word.sBx);  // Store raw int
  break;
```

**File targets:**
- `lib/src/lua_bytecode/vm_frame.dart` — add `setRawRegister()` / `rawRegister()`
- `lib/src/lua_bytecode/vm.dart` — change LOADI/LOADF/LOADK/LOADNIL handlers
- `lib/src/lua_bytecode/vm_arithmetic.dart` — read raw primitives from registers
- `lib/src/lua_bytecode/vm_value_helpers.dart` — add boxing-on-demand helpers

**Key insight:** The `LuaSlot` type is `Object?` — it can already hold raw
`int`, `double`, `bool`, `null` without wrapping. The `rawLuaSlot()` function
already unwraps `Value` objects to their raw payload. We need to:

1. **Change register storage type** from `List<Value>` to `List<Object?>`
2. **Add `setRawRegister(int index, Object? raw)`** that stores the raw value
3. **Add `rawRegister(int index)`** that reads the raw value directly
4. **Add `ensureValue(int index)`** that boxes only when a `Value` is needed
   (e.g., when passing to external functions, storing in tables, debugging)

**Implementation (~200 lines):**

```dart
// In vm_frame.dart:
late final List<Object?> registers;  // Changed from List<Value>

@pragma('vm:prefer-inline')
Object? rawRegister(int index) =>
    index < registers.length ? registers[index] : null;

@pragma('vm:prefer-inline')
void setRawRegister(int index, Object? raw) {
  if (index >= registers.length) { /* grow */ }
  registers[index] = raw;
}

/// Box a register slot into a Value only when the public API requires it.
@pragma('vm:prefer-inline')
Value ensureValue(int index) {
  final slot = rawRegister(index);
  if (slot is Value) return slot;
  return valueFromLuaSlot(runtime, slot);
}
```

```dart
// In vm.dart hot loop:
case Opcode.loadI:
  frame.setRawRegister(word.a, word.sBx);  // Raw int, no allocation
  break;

case Opcode.loadK:
  frame.setRawRegister(word.a, _constantRaw(prototype, word.bx));
  break;

case Opcode.add:
  final left = frame.rawRegister(word.b);
  final right = frame.rawRegister(word.c);
  final result = _addRaw(left, right);  // Raw int+int fast path
  frame.setRawRegister(word.a, result);
  break;
```

**Test case:**
```lua
-- test/boxing_elimination.lua
-- Tight loop that should not allocate Value wrappers
local s = 0
for i = 1, 1000000 do
  s = s + i
end
print(s)  -- 500000500000
-- Verify: no GC pressure increase, speed improvement
```

**Verification approach:**
1. Run `dart test test/lua_bytecode/` to ensure all bytecode tests pass
2. Run tight arithmetic loop benchmark before/after
3. Profile with `dart run bin/main.dart --debug` to verify no allocation increase
4. Compare GC stats before/after

**Risk:** Medium — must audit all register read sites. The `LuaSlot` infrastructure
already provides primitive detection, but any code path that assumes registers
contain `Value` objects will break. Key audit points:
- `frame.register(index)` → must return `Value` (use `ensureValue()`)
- `frame.setRegister(index, value)` → must accept `Value` (use `setRawRegister()`)
- Upvalue read/write → must box when crossing closure boundaries
- Debug info access → must box for public API
- Table stores → must box when storing in Lua tables

**Dependency:** None. Can be done independently of other optimizations.

---

## Phase 2: Medium-Term

**Goal:** 2–5x speedup for compute-bound code, 20–40% for table-heavy code.
**Risk:** Medium. Requires VM-level changes with more interaction points.

### 2.1 Integer-Only Fast Path for Arithmetic

**What:** Lua 5.4 introduced the integer/number distinction. Most loop counters
and array indices are integers. An integer-only fast path avoids `double`
boxing, NaN checks, and type promotion.

**LuaJIT reference:** `lj_ir.h` defines `IR_ADD`, `IR_SUB`, `IR_MUL` with
integer-only variants. Lua 5.4 `lopcodes.h` has `ADDI` (add integer constant)
but no register-register integer add.

**File targets:**
- `lib/src/lua_bytecode/opcode.dart` — add `ADD_RR_I`, `SUB_RR_I`, `MUL_RR_I`
- `lib/src/ir/opcode.dart` — add IR-level integer opcodes
- `lib/src/ir/emitter.dart` — emit integer opcodes when both operands are known int
- `lib/src/lua_bytecode/vm.dart` — add VM handlers

**New opcodes:**
```dart
// In Opcode enum:
addRrI(80, 'ADD_RR_I', LuaBytecodeInstructionMode.iabc),  // r[a] = r[b] + r[c] (int only)
subRrI(81, 'SUB_RR_I', LuaBytecodeInstructionMode.iabc),
mulRrI(82, 'MUL_RR_I', LuaBytecodeInstructionMode.iabc),
divRrI(83, 'DIV_RR_I', LuaBytecodeInstructionMode.iabc),
```

**VM handler:**
```dart
case Opcode.addRrI:
  final left = frame.rawRegister(word.b);
  final right = frame.rawRegister(word.c);
  if (left is int && right is int) {
    // Fast path: raw int + int
    final result = left + right;
    // Check for overflow → promote to BigInt (Lua 5.4 semantics)
    if (result > NumberLimits.maxSafeInteger || result < NumberLimits.minSafeInteger) {
      frame.setRawRegister(word.a, BigInt.from(left) + BigInt.from(right));
    } else {
      frame.setRawRegister(word.a, result);
    }
  } else {
    // Fallback: general path
    _executeBinaryInstruction(frame, ...);
  }
  break;
```

**Emitter logic:**
```dart
// In the IR emitter, when emitting ADD r, b, c:
if (registerConstFlags[b] == RegisterConstFlag.isInteger &&
    registerConstFlags[c] == RegisterConstFlag.isInteger) {
  emit(Opcode.addRrI, a: targetReg, b: leftReg, c: rightReg);
} else {
  emit(Opcode.add, a: targetReg, b: leftReg, c: rightReg);
}
```

**Test case:**
```lua
-- test/integer_fast_path.lua
local s = 0
for i = 1, 1000000 do
  s = s + i
end
print(s)  -- 500000500000
-- Verify: uses ADD_RR_I in tight loop, 2-3x faster than generic ADD
```

**Risk:** Medium — must verify integer overflow behavior matches Lua 5.4 semantics
(automatic BigInt promotion). Must handle edge cases: MIN_INT + MIN_INT overflow.

**Dependency:** Benefits from Phase 1.5 (boxing elimination) for maximum impact.

---

### 2.2 Type Specialization in Bytecode Emitter

**What:** The `TypeNarrowingPass` tracks types through `type()` checks but doesn't
propagate this to bytecode emission. Extending type tracking to the emitter
enables specialized opcodes for known-integer registers.

**File targets:**
- `lib/src/ir/prototype.dart` — extend `registerConstFlags` to include type info
- `lib/src/ir/emitter.dart` — propagate type annotations from AST
- `lib/src/ir/bytecode_lowering.dart` — encode type annotations in prototype

**Type tracking approach:**
```dart
enum RegisterConstFlag {
  unknown,
  isInteger,    // From LOADI, for-loop counter, type(x)=='number' narrowing
  isFloat,      // From LOADF, division result
  isString,     // From LOADK with string constant
  isTable,      // From NEWTABLE, known-shape table
  isNil,        // From LOADNIL
  isBoolean,    // From LOADTRUE/LOADFALSE
}

// In the emitter, propagate types:
void _emitNumericBinary(BinaryExpression expr, ...) {
  final leftType = _typeOf(expr.left);
  final rightType = _typeOf(expr.right);
  if (leftType == RegisterConstFlag.isInteger &&
      rightType == RegisterConstFlag.isInteger) {
    emitIntegerBinary(expr.operator, a: targetReg, b: leftReg, c: rightReg);
  } else {
    emitGenericBinary(expr.operator, a: targetReg, b: leftReg, c: rightReg);
  }
}
```

**Test case:**
```lua
-- test/type_specialization.lua
local function sum(arr)
  local s = 0
  for i = 1, #arr do
    s = s + arr[i]  -- i is known integer, s is known integer
  end
  return s
end
print(sum({1,2,3,4,5}))  -- 15
```

**Risk:** Medium — type inference must be sound (conservative on unknown).
Incorrect specialization causes runtime type errors. Must fall back to generic
path on type mismatch.

**Dependency:** Phase 2.1 (integer fast path opcodes).

---

### 2.3 Table Inline Caches for Known Shapes

**What:** `GETFIELD`/`SETFIELD` call `_tryFastTableGetStringKey` which checks the
raw table storage but falls back to metamethod calls. No caching of lookup
results. Inline caching records the metatable ID and hash/array offset.

**LuaJIT reference:** LuaJIT's `BC_TGETS`/`BC_TSETS` use inline caches with
a fast-path check: if the table's metatable matches the cached metatable and
the field offset matches, use the cached offset directly.

**File target:** `lib/src/lua_bytecode/vm_tables.dart`

**Cache structure:**
```dart
class TableInlineCache {
  int? metatableId;
  String? fieldName;
  int? arrayOffset;    // For array-style access
  int? hashOffset;     // For hash-style access
  bool isSlot;         // True if offset points to a raw slot

  bool hit(Map table, String field) {
    return identical(table.metatableId, metatableId) &&
           fieldName == field;
  }

  void record(Map table, String field, int offset, bool isSlot) {
    metatableId = table.metatableId;
    fieldName = field;
    arrayOffset = isSlot ? offset : null;
    hashOffset = isSlot ? null : offset;
    this.isSlot = isSlot;
  }
}
```

**VM handler modification:**
```dart
case Opcode.getField:
  final receiver = frame.rawRegister(word.b);
  final rawKey = stringConstantRaw(prototype, word.c);

  // Inline cache check
  final ic = _getFieldIC[word.a];  // Per-register IC
  if (receiver is Map && ic != null && ic.hit(receiver, rawKey)) {
    // Cache hit: direct offset access
    final value = receiver.storage[ic.arrayOffset ?? ic.hashOffset];
    frame.setRawRegister(word.a, value);
    break;
  }

  // Cache miss: normal path + record
  final fastValue = _tryFastTableGetStringKey(receiver, rawKey);
  if (fastValue != null) {
    if (receiver is Map) {
      ic?.record(receiver, rawKey, _lastOffset, _lastIsSlot);
    }
    frame.setRawRegister(word.a, fastValue);
    break;
  }
  // ... metamethod fallback
```

**Test case:**
```lua
-- test/table_inline_cache.lua
local t = {x = 1, y = 2, z = 3}
local s = 0
for i = 1, 1000000 do
  s = s + t.x + t.y + t.z  -- Same table, same fields → IC hit
end
print(s)  -- 6000000
-- Verify: IC hit rate > 99% after warmup
```

**Risk:** Low — IC is a standard VM optimization. Cache miss falls back to normal
path. Must invalidate cache when table metatable changes.

**Dependency:** Benefits from Phase 1.5 (raw register access).

---

### 2.4 Dead Store Elimination at Bytecode Level

**What:** After constant propagation, many registers are written but never read.
The AST-level `DeadCodeEliminationPass` only removes unused module exports.
Bytecode-level DSE removes pure register stores where the register is never
read before the next write or function return.

**File target:** `lib/src/ir/peephole_pass.dart`

**Approach (~120 lines):**
```dart
// Build liveness map: for each PC, which registers are read
final readBeforeWrite = <int, Set<int>>{};
for (var i = code.length - 1; i >= 0; i--) {
  final inst = code[i];
  final reads = _readsRegisters(inst);
  final writes = _writesRegisters(inst);
  // A store is dead if the register is not read before the next write
  if (writes.isNotEmpty && !_isSideEffecting(inst)) {
    for (final reg in writes) {
      if (!readBeforeWrite[i].contains(reg)) {
        // This store is dead — remove it
        result.removeAt(i);
        changed = true;
      }
    }
  }
  // Propagate reads upward
  readBeforeWrite[i - 1] = reads.union(readBeforeWrite[i] ?? {});
}
```

**Safety:** Must preserve side effects. Only eliminate pure register stores
(`MOVE`, `LOADI`, `LOADK`, `LOADNIL`, `LOADTRUE`, `LOADFALSE`). Do NOT
eliminate `SETTABLE`, `SETFIELD`, `SETLIST`, `CALL`, etc.

**Test case:**
```lua
-- test/dead_store_elimination.lua
local x = 5
x = 10  -- Dead store: x is overwritten before read
local y = x + 1
print(y)  -- 11
-- Expected: first `x = 5` store eliminated
```

**Risk:** Low — only eliminate pure register stores, preserve all side effects.

---

## Phase 3: SSA IR Foundation

**Goal:** Transformative infrastructure enabling 5–20x improvement ceiling.
**Risk:** High — massive architectural change, but foundational for all advanced
optimizations.

### 3.1 SSA-Based IR Design

**Reference:** LuaJIT `lj_ir.h` (IR instruction format), `lj_opt_fold.c`
(optimization framework). Lua 5.4 `lcode.c` (register allocation).

**Key design decisions:**

#### 3.1.1 IR Instruction Format

```dart
/// SSA instruction in lualike IR.
///
/// Format mirrors LuaJIT's IR instruction layout:
/// - opcode (8 bits)
/// - operation type (8 bits)  
/// - two operands (16 bits each) — can be constants, registers, or phi references
/// - result register (16 bits)
class SsaInstruction {
  final SsaOpcode opcode;
  final SsaType type;          // int64, float64, string, ref, void
  final SsaOperand op1;        // Left operand
  final SsaOperand op2;        // Right operand (for binary ops)
  final int result;            // Result register
  final int pc;                // Source PC for debug info
}

/// An operand can be a constant, a register, a phi reference, or undefined.
sealed class SsaOperand {
  const SsaOperand();
}

class SsaConstant extends SsaOperand {
  final Object? value;  // int, double, String, bool, null
  const SsaConstant(this.value);
}

class SsaRegister extends SsaOperand {
  final int index;
  const SsaRegister(this.index);
}

class SsaPhi extends SsaOperand {
  final int phiNode;  // Index into the phi node list
  const SsaPhi(this.phiNode);
}
```

#### 3.1.2 Basic Block Structure

```dart
/// A basic block in SSA form.
class SsaBasicBlock {
  final int id;
  final List<SsaBasicBlock> predecessors;
  final List<SsaBasicBlock> successors;
  final List<SsaInstruction> instructions;
  final List<SsaPhi> phiNodes;  // Phi functions at merge points
  final SsaTerminator? terminator;  // JMP, RETURN, etc.

  // Dominance info
  SsaBasicBlock? immediateDominator;
  final Set<SsaBasicBlock> dominatorTreeChildren = {};
  int dominatorTreeIndex = 0;
  int dominatorTreeSize = 0;  // For Lengauer-Tarjan
}

sealed class SsaTerminator {
  const SsaTerminator();
}

class SsaJump extends SsaTerminator {
  final SsaBasicBlock target;
  const SsaJump(this.target);
}

class SsaConditionalJump extends SsaTerminator {
  final SsaBasicBlock trueTarget;
  final SsaBasicBlock falseTarget;
  final SsaRegister condition;
  const SsaConditionalJump(this.condition, this.trueTarget, this.falseTarget);
}

class SsaReturn extends SsaTerminator {
  final List<SsaRegister> values;
  const SsaReturn(this.values);
}
```

#### 3.1.3 IR Opcodes

```dart
enum SsaOpcode {
  // Constants
  constInt, constFloat, constString, constBool, constNil,
  
  // Arithmetic (typed)
  addInt, subInt, mulInt, divInt, modInt, idivInt, powInt,
  addFloat, subFloat, mulFloat, divFloat, modFloat, idivFloat, powFloat,
  
  // Mixed (int op float → float result)
  addIntFloat, subIntFloat, mulIntFloat, divIntFloat,
  
  // Comparison
  eqInt, ltInt, leInt, eqFloat, ltFloat, leFloat,
  eqRef, ltRef, leRef,  // Reference comparison
  
  // Logical
  and, or, not,
  
  // Bitwise
  band, bor, bxor, shl, shr, bnot,
  
  // Memory
  load, store,
  loadField, storeField,
  loadIndex, storeIndex,
  
  // Control
  call, tailCall, ret,
  phi,
  
  // Type checks (for guards)
  checkInt, checkFloat, checkString, checkTable,
  
  // Conversion
  intToFloat, floatToInt,
}
```

#### 3.1.4 The IR Compiler

```dart
/// Converts lualike bytecode to SSA IR.
class BytecodeToSsa {
  final SsaFunction function;
  final Map<int, SsaBasicBlock> pcToBlock = {};
  
  SsaFunction compile(LuaBytecodePrototype proto) {
    // Step 1: Build basic blocks from bytecode
    final blocks = _buildBasicBlocks(proto);
    
    // Step 2: Convert to SSA form
    _convertToSsa(blocks);
    
    // Step 3: Compute dominance
    _computeDominance(blocks);
    
    // Step 4: Rename variables (SSA naming)
    _renameVariables(blocks);
    
    return function;
  }
}
```

**Migration strategy:**
1. Build SSA IR infrastructure alongside existing bytecode
2. Implement a simple bytecode→SSA converter
3. Run SSA optimizations to produce optimized SSA
4. Lower optimized SSA back to bytecode (existing emitter)
5. Gradually shift more optimization to SSA, less to peephole

**Test case:**
```lua
-- test/ssa_basic.lua
local function fib(n)
  if n <= 1 then return n end
  return fib(n-1) + fib(n-2)
end
print(fib(30))  -- 832040
-- Verify: SSA form has phi nodes at merge points, dominance is correct
```

**Risk:** High — must maintain compatibility with existing bytecode emission and
the dual VM model. Must not break any existing tests.

---

### 3.2 SSA Optimization Passes

With SSA infrastructure in place, implement these passes incrementally:

#### 3.2.1 Global Value Numbering (GVN) — 300 lines

Eliminates redundant computations across basic blocks by assigning each
unique value a number. Two computations with the same inputs and operation
get the same number.

**LuaJIT reference:** `lj_opt_fold.c` — fold engine combines constant folding,
strength reduction, and CSE into a single hash-based pass.

```dart
class GvnPass {
  final Map<(SsaOpcode, List<SsaOperand>), int> valueNumbers = {};
  
  void run(SsaFunction function) {
    for (final block in function.blocks) {
      for (final inst in block.instructions) {
        final vn = _computeValueNumber(inst);
        if (valueNumbers.containsKey(vn)) {
          // Replace with existing computation
          _replaceWith(inst, valueNumbers[vn]!);
        } else {
          valueNumbers[vn] = inst.result;
        }
      }
    }
  }
}
```

**Test case:**
```lua
-- test/gvn.lua
local x = a + b
local y = a + b  -- Same as x → eliminated
local z = x + y  -- Uses x twice
print(z)
```

**Risk:** Medium — must handle side effects correctly (don't eliminate
expressions with side effects).

---

#### 3.2.2 Sparse Conditional Constant Propagation (SCCP) — 400 lines

More powerful than AST-level folding. Propagates constants through both
data flow and control flow, eliminating dead branches.

**LuaJIT reference:** `lj_opt_fold.c` — SCCP integrated into the fold engine.

```dart
class SccpPass {
  final Map<int, LatticeValue> values = {};
  final Set<SsaBasicBlock> reachableBlocks = {};
  
  enum LatticeValue { top, bottom, constant(Object?) }
  
  void run(SsaFunction function) {
    // Worklist algorithm
    final worklist = Queue<SsaWorkItem>();
    worklist.add(SsaWorkItem.entry(function));
    
    while (worklist.isNotEmpty) {
      final item = worklist.removeFirst();
      _evaluateItem(item, worklist);
    }
    
    // Replace constants and remove dead branches
    _replaceConstants(function);
    _removeDeadBranches(function);
  }
}
```

**Test case:**
```lua
-- test/sccp.lua
local x = 5
local y = x * 2  -- Fold to 10
local z = y + 3  -- Fold to 13
if false then
  print("dead")  -- Eliminated
end
print(z)  -- 13
```

**Risk:** Medium — must handle phi nodes and loops correctly.

---

#### 3.2.3 Loop Invariant Code Motion (LICM) — 250 lines

Hoists loop-invariant computations out of loops.

**LuaJIT reference:** LuaJIT doesn't implement LICM explicitly (it relies on
SSCP + loop unrolling), but it's a standard SSA optimization.

```dart
class LicmPass {
  void run(SsaFunction function) {
    for (final loop in function.loops) {
      final invariants = _findLoopInvariants(loop);
      for (final inst in invariants) {
        // Move to loop preheader
        loop.preheader.instructions.add(inst);
        inst removeFrom loop block;
      }
    }
  }
}
```

**Test case:**
```lua
-- test/licm.lua
local t = {1, 2, 3, 4, 5}
local x = 10  -- Loop-invariant
local s = 0
for i = 1, #t do
  s = s + t[i] + x  -- x + is loop-invariant, hoisted
end
print(s)  -- 35
```

**Risk:** Low — must not hoist side-effecting operations or operations that
may not execute (guarded by loop condition).

---

#### 3.2.4 Register Coalescing — 200 lines

Eliminates MOVE instructions by assigning the same physical register to
source and destination when they don't interfere.

**LuaJIT reference:** `lj_regalloc.h` — linear scan register allocation.

```dart
class RegisterCoalescer {
  void run(SsaFunction function) {
    // Build interference graph
    final interference = _buildInterferenceGraph(function);
    
    // For each MOVE a, b:
    //   If a and b don't interfere, merge them
    for (final block in function.blocks) {
      for (final inst in block.instructions) {
        if (inst.opcode == SsaOpcode.move) {
          final src = inst.op1 as SsaRegister;
          final dst = SsaRegister(inst.result);
          if (!_interfere(src, dst, interference)) {
            _coalesce(src, dst);
          }
        }
      }
    }
  }
}
```

**Risk:** Low — standard SSA optimization with well-understood correctness.

---

## Phase 4: Advanced Optimizations

**Goal:** Approach LuaJIT performance for integer-heavy workloads.
**Risk:** High for JIT, Medium for others.

### 4.1 Function Inlining at Bytecode Level

**What:** Inline small, frequently-called functions to eliminate call overhead.

**Heuristics (from LuaJIT `lj_opt_fold.c`):**
- Inline only functions with < 16 instructions
- Inline only when all arguments are known types
- Don't inline functions with upvalues (unless single-return, no closures)
- Don't inline if the function is recursive

**Implementation approach:**
```dart
class FunctionInliner {
  void run(SsaFunction function) {
    for (final block in function.blocks) {
      for (final inst in block.instructions) {
        if (inst.opcode == SsaOpcode.call) {
          final target = _resolveCallee(inst);
          if (target != null && _shouldInline(target)) {
            _inlineFunction(block, inst, target);
          }
        }
      }
    }
  }
  
  bool _shouldInline(SsaFunction callee) {
    return callee.instructionCount < 16 &&
           !callee.hasUpvalues &&
           !callee.isRecursive &&
           callee.argumentTypes.every((t) => t != SsaType.unknown);
  }
}
```

**Risk:** High — must handle upvalues correctly, preserve debugging semantics,
and avoid code bloat. Only inline when profiling shows the function is hot.

**Dependency:** SSA IR (Phase 3.1).

---

### 4.2 JIT Compilation for Hot Loops

**What:** Compile hot loops to native machine code via Dart's FFI or a custom
code generator.

**LuaJIT reference:** `lj_asm_x86.h` — x86/x64 code generator. `lj_record.c`
— trace recording and compilation.

**Implementation approach (high-level):**

1. **Profile-guided instrumentation:**
   - Count back-edges in loops (increment counter at JMP backward)
   - When counter exceeds threshold (e.g., 1000 iterations), trigger compilation

2. **Trace recording:**
   - Record the actual execution path through the loop
   - Record type information at each operation

3. **IR generation:**
   - Convert recorded trace to SSA IR with type specialization
   - Apply SSA optimizations

4. **Native code generation:**
   - Lower SSA IR to machine code
   - Use Dart's FFI for native code execution
   - Emit type guards with side exits

5. **Deoptimization:**
   - On type mismatch, deoptimize back to interpreter
   - Restore interpreter state from snapshot

**Risk:** Very High — native code generation is complex, debugging is difficult,
and correctness is hard to verify.

**Dependency:** SSA IR (Phase 3.1), type specialization (Phase 2.2).

---

### 4.3 Generational GC with Write Barriers

**What:** The GC infrastructure already supports generations
(`lib/src/gc/generational_gc.dart`), but the VM doesn't use write barriers
to track old-to-young pointers.

**File target:** `lib/src/lua_bytecode/vm_tables.dart` (table stores)

**Implementation (~500 lines):**

```dart
// In table store operations:
void _tableSetWithWriteBarrier(Map table, Object? key, Object? value) {
  table[key] = value;
  
  // Write barrier: if table is old-gen and value is young-gen,
  // record the pointer in the remembered set
  if (_isOldGen(table) && _isYoungGen(value)) {
    _rememberedSet.add(table);
  }
}

// During minor GC:
void _minorCollect() {
  // Only scan nursery + remembered set
  _scanNursery();
  for (final oldRef in _rememberedSet) {
    _scanForYoungPointers(oldRef);
  }
  _rememberedSet.clear();
}
```

**Risk:** Medium — write barriers add overhead to every store but reduce total
GC time. Must measure to verify net positive.

---

### 4.4 Scalar Replacement of Aggregates

**What:** Eliminate table allocations for tables with known structure where
all fields are accessed directly.

**LuaJIT reference:** LuaJIT doesn't implement SRA (it relies on escape
analysis + allocation sinking), but it's a standard optimization.

```dart
class ScalarReplacement {
  void run(SsaFunction function) {
    for (final inst in function.instructions) {
      if (inst.opcode == SsaOpcode.newTable) {
        final fields = _analyzeFieldAccesses(inst);
        if (fields != null && !_escapes(inst)) {
          // Replace table allocation with individual registers
          _replaceWithScalars(inst, fields);
        }
      }
    }
  }
}
```

**Risk:** Medium — must handle all edge cases where the table escapes
(passed to external functions, stored in other tables, etc.).

---

### 4.5 Escape Analysis

**What:** Determine if objects escape the current scope, enabling scalar
replacement and allocation sinking.

**LuaJIT reference:** LuaJIT performs escape analysis in `lj_opt_mem.c`.

```dart
class EscapeAnalysis {
  void run(SsaFunction function) {
    // Mark escaping allocations
    for (final inst in function.instructions) {
      if (_isAllocation(inst)) {
        if (_escapes(inst, function)) {
          _markEscaping(inst);
        }
      }
    }
  }
  
  bool _escapes(SsaInstruction alloc, SsaFunction function) {
    // Check if the allocation is:
    // 1. Stored in a global or upvalue
    // 2. Passed to an external function
    // 3. Returned from the current function
    // 4. Stored in an escaping table
    // ...
  }
}
```

**Risk:** Medium — must be conservative (mark as escaping if unsure).

---

## Metrics & Benchmarks

### Baseline Measurements

Run these before starting optimization work:

```bash
# 1. Arithmetic tight loop (measures boxing overhead)
dart run bin/main.dart -e "
local s = 0
for i = 1, 1000000 do s = s + i end
print(s)
" 2>&1 | tail -1
# Record: time, GC pauses

# 2. Table access loop (measures table lookup overhead)
dart run bin/main.dart -e "
local t = {}
for i = 1, 100000 do t[i] = i end
local s = 0
for i = 1, 100000 do s = s + t[i] end
print(s)
" 2>&1 | tail -1

# 3. String concatenation (measures string interning)
dart run bin/main.dart -e "
local s = ''
for i = 1, 100000 do s = s .. 'a' end
print(#s)
" 2>&1 | tail -1

# 4. Function call overhead (measures call/return cost)
dart run bin/main.dart -e "
local function f(x) return x + 1 end
local s = 0
for i = 1, 100000 do s = f(s) end
print(s)
" 2>&1 | tail -1

# 5. Full test suite (measures regression)
dart test
```

### Target Metrics

| Metric | Baseline | Phase 1 | Phase 2 | Phase 3 |
|--------|----------|---------|---------|---------|
| Arithmetic loop (ms) | [measure] | -10% | -50% | -90% |
| Table loop (ms) | [measure] | -5% | -40% | -80% |
| String loop (ms) | [measure] | -5% | -20% | -60% |
| Function call (ms) | [measure] | -5% | -30% | -70% |
| Test suite (s) | [measure] | 0% | -20% | -50% |
| Allocations/op | [measure] | -30% | -80% | -95% |

### Verification Approach

For each optimization:
1. **Correctness:** Run full test suite (`dart test`)
2. **Performance:** Run benchmark suite, compare before/after
3. **Memory:** Profile allocation rate, verify no increase
4. **Regression:** Run integration tests with real Lua scripts

---

## Reference Sources

### LuaJIT References
- `lj_ir.h` — IR instruction format, opcode definitions
- `lj_opt_fold.c` — Fold engine (GVN, SCCP, strength reduction)
- `lj_opt_mem.c` — Memory optimization (escape analysis, load/store)
- `lj_asm_x86.h` — x86/x64 native code generation
- `lj_record.c` — Trace recording and compilation
- `lj_regalloc.h` — Register allocation (linear scan)
- `lj_bc.h` — Bytecode format and instruction encoding

### Lua 5.4 References
- `lopcodes.h` — Opcode definitions and instruction formats
- `lcode.c` — Code generation and register allocation
- `lvm.c` — Virtual machine execution loop
- `lgc.c` — Garbage collector (generational mode)

### Lualike-Specific References
- `lib/src/ir/peephole_pass.dart` — Existing IR peephole pass
- `lib/src/lua_bytecode/peephole_pass.dart` — Existing bytecode peephole pass
- `lib/src/runtime/lua_slot.dart` — Raw primitive slot system
- `lib/src/lua_bytecode/vm_frame.dart` — Frame register storage
- `lib/src/lua_bytecode/vm.dart` — Main VM execution loop
- `lib/src/lua_bytecode/vm_arithmetic.dart` — Arithmetic fast paths
- `lib/src/ir/opcode.dart` — IR opcode definitions
- `lib/src/lua_bytecode/opcode.dart` — Bytecode opcode definitions
- `lib/src/gc/generational_gc.dart` — Existing generational GC infrastructure

---

## Decision Points

### After Phase 1
Profile actual workloads. If arithmetic is the bottleneck, prioritize 2.1
(integer fast path). If table access is the bottleneck, prioritize 2.3 (IC).

### After Phase 2
If integer-heavy workloads (numerical algorithms) are the primary use case,
invest in SSA + JIT. If general Lua compatibility is the priority, focus on
GC and coroutine optimizations.

### SSA vs JIT Decision
SSA alone gives 2–5x improvement without native code. JIT gives 10–100x but
with 5x more implementation effort. **Recommendation:** Ship SSA first and
JIT as a future optional enhancement.

---

