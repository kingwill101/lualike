# Garbage Collection Failure Analysis Report

## Executive Summary

The `gc.lua` test fails because **automatic garbage collection triggers are disabled** in the lualike interpreter. The garbage collector implementation is functional, but it only runs when explicitly called via `collectgarbage()`, not automatically during object allocation.

## Root Cause Analysis

### Primary Issue
**Location**: `lib/src/interpreter/interpreter.dart:653-655`
**Problem**: The automatic garbage collection trigger is commented out:

```dart
// if (gc.allocationDebt > 1024 * 1024 * 100) { // 100MB threshold for deep recursion
//   gc.triggerGCIfNeeded();
// }
```

### Impact
- Objects with `__gc` metamethods are never collected automatically
- The `gc.lua` test hangs in infinite loops waiting for garbage collection
- Memory usage grows without bounds in allocation-heavy scenarios
- Behavior differs significantly from reference Lua interpreter

## How to Reproduce the Error

### Method 1: Run the Full gc.lua Test
```bash
cd /run/media/kingwill101/disk2/code/code/dart_packages/lualike/pkgs/lualike
./test_runner --test=gc.lua --verbose
```
**Expected Result**: Test hangs indefinitely after printing "steps (2)"
**Actual Result**: Test hangs indefinitely, never completes

### Method 2: Run Minimal Reproduction Script
Create a file `reproduce_gc_hang.lua`:
```lua
-- Minimal reproduction of gc.lua hanging issue
local function GC1()
    local u
    local finish = false
    u = setmetatable({}, {
        __gc = function()
            print("u collected")
            finish = true
        end
    })
    print("Starting infinite loop...")
    repeat
        u = {}
    until finish
    print("Loop completed!")
end

print("About to call GC1()")
GC1()
print("GC1() completed")
```

Run with lualike:
```bash
dart run bin/main.dart reproduce_gc_hang.lua
```
**Expected Result**: Hangs after "Starting infinite loop..."
**Actual Result**: Hangs indefinitely, never prints "u collected"

### Method 3: Compare with Reference Lua
Run the same script with reference Lua:
```bash
lua reproduce_gc_hang.lua
```
**Expected Result**: Completes successfully, prints "u collected" and "Loop completed!"
**Actual Result**: Works correctly, demonstrates the issue is lualike-specific

## Detailed Analysis

### Test Case: GC1 Function
The failing test creates an object with a `__gc` metamethod and enters an infinite loop:

```lua
local function GC1()
    local u
    local finish = false
    u = setmetatable({}, {
        __gc = function()
            print("u collected")
            finish = true  -- This never gets set to true
        end
    })
    repeat
        u = {}  -- Creates new objects, but old ones are never collected
    until finish  -- Infinite loop because finish is never true
end
```

### Expected vs Actual Behavior

| Aspect | Reference Lua | Lualike (Current) | Lualike (Expected) |
|--------|---------------|-------------------|-------------------|
| Automatic GC | ✅ Works | ❌ Disabled | ✅ Should work |
| Manual GC | ✅ Works | ✅ Works | ✅ Works |
| GC1 Function | ✅ Completes | ❌ Hangs | ✅ Should complete |
| Memory Growth | ✅ Controlled | ❌ Unbounded | ✅ Should be controlled |

### Technical Details

#### Garbage Collection Implementation Status
- ✅ **GC Core Logic**: Fully implemented and functional
- ✅ **Object Registration**: Objects are properly registered with GC
- ✅ **Allocation Debt Tracking**: `_simulatedAllocationDebt` accumulates correctly
- ✅ **Manual Collection**: `collectgarbage()` works correctly
- ❌ **Automatic Triggers**: Disabled in interpreter main loop

#### Evidence from Debug Output
```
[FINE] [GC] Register table 570315026 weakMode=null
[FINE] [GC] Register: Value 570315026
[FINE] [GC] Register table 616698511 weakMode=null
[FINE] [GC] Register: Value 616698511
```
- Objects are being registered with GC
- Allocation debt is accumulating
- But no automatic collection is triggered

#### Test Results Comparison

**Reference Lua (Working)**:
```
Testing original GC1 with reference Lua...
line 64
u collected
line 67
GC1 completed successfully!
```

**Lualike (Hanging)**:
```
line 64 - about to start repeat loop
[Infinite loop - no output after this point]
```

**Lualike with Manual GC (Working)**:
```
Iteration 100 - finish = false
u collected after 100 iterations
Loop finished after 100 iterations
```

## Affected Components

### Direct Impact
1. **gc.lua test**: Hangs indefinitely
2. **Memory management**: Unbounded growth in allocation-heavy scenarios
3. **Lua compatibility**: Behavior differs from reference implementation

### Indirect Impact
1. **Test suite**: 1/14 tests failing (gc.lua)
2. **Memory leaks**: Potential in long-running scripts
3. **Performance**: Degradation in memory-intensive applications

## Recommended Solution

### Immediate Fix
Uncomment and adjust the automatic garbage collection trigger in `lib/src/interpreter/interpreter.dart`:

```dart
// Current (commented out):
// if (gc.allocationDebt > 1024 * 1024 * 100) { // 100MB threshold for deep recursion
//   gc.triggerGCIfNeeded();
// }

// Recommended fix:
if (gc.allocationDebt > 1024 * 1024) { // 1MB threshold (more reasonable)
  gc.triggerGCIfNeeded();
}
```

### Considerations
1. **Threshold Tuning**: The original 100MB threshold was likely too high
2. **Performance Impact**: Need to balance GC frequency vs performance
3. **Test Validation**: Must verify all existing tests still pass
4. **Memory Usage**: Monitor for any memory usage regressions

## How to Verify the Fix

### Step 1: Apply the Fix
Uncomment and modify the GC trigger in `lib/src/interpreter/interpreter.dart:653-655`:
```dart
// Change from:
// if (gc.allocationDebt > 1024 * 1024 * 100) { // 100MB threshold for deep recursion
//   gc.triggerGCIfNeeded();
// }

// To:
if (gc.allocationDebt > 1024 * 1024) { // 1MB threshold
  gc.triggerGCIfNeeded();
}
```

### Step 2: Test the Reproduction Script
Run the minimal reproduction script:
```bash
dart run bin/main.dart reproduce_gc_hang.lua
```
**Expected Result**: Should print "u collected" and "Loop completed!" instead of hanging

### Step 3: Run the Full Test Suite
```bash
./test_runner --verbose
```
**Expected Result**: All 14/14 tests should pass, including gc.lua

### Step 4: Compare with Reference Lua
Run the same script with reference Lua to ensure behavior matches:
```bash
lua reproduce_gc_hang.lua
```
**Expected Result**: Both lualike and reference Lua should behave identically

## Validation Plan

### Test Cases to Verify
1. **gc.lua**: Should complete without hanging
2. **All existing tests**: Should continue to pass
3. **Memory stress test**: Verify bounded memory growth
4. **Performance test**: Ensure reasonable GC overhead

### Success Criteria
- [ ] gc.lua test passes
- [ ] All 14/14 tests pass
- [ ] Memory usage remains bounded in allocation-heavy scenarios
- [ ] Performance impact is acceptable (< 10% overhead)

## Risk Assessment

### Low Risk
- **Core GC Logic**: Already implemented and tested
- **Manual Collection**: Proven to work correctly
- **Object Registration**: Functioning properly

### Medium Risk
- **Performance Impact**: Automatic GC may affect performance
- **Threshold Tuning**: May require iteration to find optimal values
- **Edge Cases**: Some scenarios may behave differently

### Mitigation
- Start with conservative threshold (1MB)
- Monitor test suite performance
- Implement gradual rollout with performance monitoring

## Conclusion

The garbage collection failure is caused by a simple configuration issue - automatic GC triggers are disabled. The fix is straightforward but requires careful tuning of the allocation threshold to balance performance and memory management. This is a critical fix for Lua compatibility and memory safety.

