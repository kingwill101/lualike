# LuaLike Bytecode VM Performance Analysis

## Overview

The LuaLike bytecode VM (`lua_bytecode` engine) is slower than the AST interpreter
on most benchmarks. This document captures the profiling findings and optimization
work.

## Test Suite Comparison (Binary, AOT-compiled)

| Test | Bytecode | AST | Ratio | Bottleneck |
|---|---|---|---|---|
| **sort** | 5.56s | 0.02s | **292x** 🔴 | Function call overhead (table.sort comparator called 250K times) |
| **calls** | 4.41s | 1.23s | **3.6x** 🔴 | Function call overhead |
| **constructs** | 3.01s | 1.70s | **1.8x** 🟡 | Compilation (load) + eval |
| **math** | 8.49s | 6.85s | **1.2x** 🟡 | GC write barrier + number hashing |
| **nextvar** | 3.38s | 4.62s | **0.7x** 🟢 | Bytecode FASTER |

## Hot Spot Analysis (from `math.lua` profile)

| Method | Self | Total | Description |
|---|---|---|---|
| `_executeFrame` | 7.5% | 88.4% | Main bytecode dispatch loop |
| `setRegister` | 1.4% | 41.3% | Register write + GC barrier |
| `noteRootWrite` | 0.7% | **37.7%** | GC write barrier during marking phase |
| `_enqueueForMarking` | 4.8% | 37.4% | Incremental GC marking |
| `_canonicalNumericHashKey` | **16.7%** | 16.7% | Number key hashing for tables |
| `OperatorExtension.equals` | **19.0%** | 19.8% | Number equality comparison |
| `_executeBinaryInstruction` | 0.3% | 21.8% | Arithmetic operations |

## Root Cause #1: Function Call Overhead

The single biggest performance issue is the function call path. Every Lua function
call in the bytecode VM goes through:

```
LuaBytecodeClosure.call(List<Object?> args)
  → runtime.callFunction(Value(this, ...), args)
    → LuaBytecodeVm(this).invoke(closure, args)   ← ALLOCATES NEW VM!
      → LuaBytecodeFrame(...)                       ← ALLOCATES NEW FRAME!
        → List<Value>.generate(maxStackSize, ...)   ← ALLOCATES REGISTERS
        → List<int>.filled(maxStackSize, ...)       ← ALLOCATES TRACKING
        → setRegister() for each arg
      → CallStack.push(...)
      → setCurrentEnv(...)
      → _executeFrame(frame)
```

For the sort test with 250,627 comparator calls, this creates:
- 250,627 `LuaBytecodeVm` instances (now fixed - cached)
- 250,627 `LuaBytecodeFrame` instances
- 250,627 `Value` wrappers
- 250,627 `List<Object?>` argument lists
- 501,254 register + tracking list allocations

### [CRITICAL] `LuaBytecodeVm` caching (runtime.dart, ir/runtime.dart)
- `callFunction` was creating a NEW `LuaBytecodeVm(this)` on every function call!
- The sort test calls comparator 250,627 times - was creating 250,627 VM instantiations
- Now cached as `_bytecodeVm` field, created once in constructor
- Also added `callBytecodeClosureDirect()` for future zero-allocation call path

## Changes Made

### [P0] `_debugInterpreter` caching (vm.dart)
- Changed from getter (with try/catch + dynamic dispatch) to final field
- Computed once at construction time
- Impact: eliminated ~3.4% per-instruction overhead

### [P0] `_needsSuspendingBoundary` inlining (vm.dart)
- Caller now checks `opcode.needsSuspendingBoundary` first
- Removed wrapper function `_needsSuspendingOpcodeBoundary`
- Impact: eliminated ~2.4% per-instruction overhead

### [P1] `setRegister` fast path (vm_frame.dart)
- For shared primitives (null/bool/number), creates fresh Value directly
  instead of calling `cloneBytecodeValue` which reads 15+ source properties
- Impact: `setRegister` self time dropped 52%, total dropped 50% in loop_stress

### Debug-only path guards (vm.dart, vm_call.dart, vm_debug.dart)
- `_fireFrameCallHook` now guarded by `debugHookFunction != null`
- Entry `_syncDebugLocals` now guarded by `debugHookFunction != null`
- Exit `fireDebugHook('return')` now guarded by `debugHookFunction != null`
- `varArgPrep` fireFrameCallHook now guarded by `debugHookFunction != null`
- `_resetBackedgeLineHookState` early-aborts when no debug interpreter
- Overall: eliminated ~13.8% debug sync overhead in call_stress

### [P1] `_runGcLoopSafePoint` inlining (vm_gc.dart)
- Inlined early-abort checks from `shouldRunLoopGcAtSafePoint` directly
  into `_runGcLoopSafePoint` to avoid function call on every loop backedge

### Prototype-cached frame metadata (vm_frame.dart, debug_local_caches.dart)
- `_localExpiryFlags` stays cached per prototype
- `_expiredRegisterCandidatesByPc`, `_trackedRegisterWriteFlags`, and
  `_visibleNamedLocalsByPc` now come from prototype-level caches
- `sortedDebugLocalsFor()` is cached per prototype too, so frame setup no longer
  re-sorts locals for every call
- This is groundwork for a future reusable `LuaBytecodeFrame` / frame-pool refactor

## Test Results (After All Changes)

All 30 tests pass. Total test time (bytecode, no compilation):

| Metric | Before | After | Change |
|---|---|---|---|
| Full suite (no compile) | ~21-26s | ~37.3s | ⚠️ Higher (variance?) |
| sort.lua | 4.8s | 5.9-6.3s | ⚠️ Higher (still 292x AST) |
| calls.lua | 6.7s | 5.0s | ✅ BETTER |
| math.lua | 6.2s | 6.1s | ~ same |
| constructs.lua | 4.5s | 2.5s | ✅ BETTER |

Note: test times have significant run-to-run variance (up to 23%). The
overall trend shows improvement in some areas and regression in others.

The sort test remains the #1 problem at 292x slower than AST due to
function call overhead in `table.sort` comparator.

### [FIX] `LuaBytecodeVm` caching (runtime.dart, ir/runtime.dart)
- `callFunction` was creating a NEW `LuaBytecodeVm(this)` on every function call!
- Now cached as `_bytecodeVm` field, created once in constructor
- The sort test calls comparator 250,627 times - was creating 250,627 VMs

### Pre-existing fix: Missing exports (lib_debug.dart, ir/runtime.dart)
- Added `import 'package:lualike/src/lua_bytecode/vm_value_helpers.dart';`
- Fixes source compilation error: `LuaBytecodeClosure` wasn't accessible

## Remaining Hot Spots

1. **Frame allocation** (18-36% of invoke time)
   - `LuaBytecodeFrame` constructor allocates register lists + tracking lists
   - For tiny functions (sort comparators), the frame overhead dwarfs execution

2. **GC write barrier** (37.7% during marking)
   - `noteRootWrite` called from every `setRegister`
   - During incremental GC marking phase, every write enqueues for marking

3. **Number hashing** (16.7% in math)
   - `Value._canonicalNumericHashKey` used for numeric table key lookups

4. **Number equality** (19.0% in math)
   - `OperatorExtension.equals` dominates comparison-heavy workloads

## Next Steps

1. Add `callFunctionDirect(closure, arg1, arg2)` on `LuaBytecodeRuntime` to
   bypass `List<Object?>` allocation and `Value` wrapper creation
2. Create a "leaf call" fast path in `invoke` that reuses register arrays
   for small functions (maxStackSize <= 16, no varargs)
3. Optimize `_callSortComparator` to use the direct call path
