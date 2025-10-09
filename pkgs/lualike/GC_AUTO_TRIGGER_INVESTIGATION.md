# GC Auto-Trigger Investigation and Solution

## Problem Statement

There are two conflicting requirements for automatic garbage collection:

1. **gc.lua requires automatic GC**: The test `gc.lua` expects incremental garbage collection to run automatically based on allocation pressure. Without automatic triggering, it hangs in the GC1 and GC2 functions.

2. **calls.lua hangs with automatic GC**: The test `calls.lua` uses deep tail-recursive calls (`deep(30000)`). When GC is triggered automatically in the statement execution loop, it causes the test to hang during tail call optimization.

## Root Cause Analysis

### Why gc.lua hangs without automatic GC
- The GC1 and GC2 functions in gc.lua create objects in loops (repeat-until)
- They expect the GC to trigger automatically when allocation debt accumulates
- Without automatic triggering, memory pressure never causes GC to run

### Why calls.lua hangs with automatic GC in _executeStatements
- The `deep(30000)` function uses tail call optimization
- Tail calls throw `TailCallException` to unwind and rebind the function frame
- This happens within a single statement execution
- When GC triggers during statement execution, it interferes with the tail call mechanism
- The exact failure mode needs further investigation, but appears to be an infinite loop or deadlock

## Failed Approaches

### 1. Critical Section Protection
**Approach**: Added `enterCriticalSection()` and `exitCriticalSection()` to prevent GC during function calls.

**Problem**: Tail calls create nested "function calls" via exceptions, leading to:
- Critical section depth never reaching zero during deep recursion
- GC never running even when it should
- Both tests hanging

### 2. Statement-Level Protection
**Approach**: Wrap each statement execution in critical section enter/exit.

**Problem**: Same issue - tail calls happen within statement execution, so critical section is never exited during deep tail recursion.

## Current Partial Solution

### What Works
Added GC triggering at safe points in loop finally blocks:
- `visitWhileStatement` - after each iteration
- `visitRepeatUntilLoop` - after each iteration

This allows gc.lua's GC1/GC2 functions to trigger GC during loop execution.

### What Doesn't Work
- calls.lua still hangs because tail recursion doesn't go through loop finally blocks
- The deep tail recursive calls never hit a safe point for GC

## Recommended Solution

### Short Term: Disable Automatic GC in _executeStatements
Remove the automatic GC triggering from `_executeStatements`:
```dart
// Remove this code:
if (gc.allocationDebt > 1024 * 10) {
  gc.triggerGCIfNeeded();
}
```

Keep GC triggering only in:
1. Loop finally blocks (already added)
2. Explicit `collectgarbage()` calls from Lua code
3. Via `simulateAllocation()` when called explicitly

### Medium Term: Implement Proper Allocation Tracking
The real solution is to call `gc.simulateAllocation(bytes)` whenever we allocate:
- Tables: when creating new tables via table constructors
- Strings: when creating new string values
- Functions: when creating closures
- Other objects: upvalues, environments, etc.

This way, GC runs incrementally based on actual allocation pressure, not arbitrary points in execution.

### Long Term: Safe Point Analysis
Implement a sophisticated safe point mechanism:
1. Identify truly safe points where GC can run without interfering with VM state
2. These include:
   - Between top-level statements
   - At loop iteration boundaries
   - After function returns (not during tail calls!)
   - After metamethod execution completes
3. Never trigger GC during:
   - Tail call optimization (while TailCallException is in flight)
   - Deep in the call stack during recursion
   - During metamethod chain resolution

## Testing Strategy

1. **Test gc.lua**: Verify GC triggers during loop iterations
2. **Test calls.lua**: Verify tail calls complete without GC interference
3. **Monitor memory**: Ensure GC actually collects garbage and prevents unbounded growth
4. **Benchmark**: Measure performance impact of different GC triggering strategies

## Implementation Status

- ✅ Added GC triggering in loop finally blocks
- ✅ Removed automatic GC from `_executeStatements`
- ✅ **calls.lua now passes!** - No more hanging during tail recursion
- ⚠️ **gc.lua partially works** - No longer hangs in GC1/GC2, but fails assertion at line 475
- ❌ Need to add `simulateAllocation()` calls at allocation sites
- ❌ Need to implement proper safe point detection
- ❌ Need comprehensive testing of both approaches

## Test Results

### Current State (GC only in loop finally blocks)

**calls.lua**: ✅ PASSES
- Deep tail recursion (deep(30000)) works correctly
- No hanging, all assertions pass
- Test completes in ~22 seconds

**gc.lua**: ⚠️ FAILS (but doesn't hang)
- GC1 and GC2 functions complete without hanging
- Weak table collection partially works
- Fails at line 475: `assert(next(a) == nil)` 
- This indicates weak-keyed table entries are not being collected properly
- The GC is running but not collecting all expected garbage

### Root Cause of gc.lua Failure
The assertion failure at line 475 suggests:
1. GC is triggering during loops (good)
2. But weak table cleanup isn't working correctly
3. Objects that should be garbage collected are still being retained
4. This is likely a separate issue from the auto-trigger mechanism

## Next Steps

1. ✅ Test current changes with both gc.lua and calls.lua
2. ✅ Confirmed calls.lua passes, gc.lua fails but doesn't hang
3. 🔄 Investigate weak table collection issue in gc.lua (separate from auto-trigger)
4. Consider accepting current state as improvement: **no more hangs!**
5. Address weak table collection as a separate issue
6. Implement proper allocation tracking as the long-term solution
