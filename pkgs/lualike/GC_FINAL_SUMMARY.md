# GC Weak Table Collection - Final Status Report

## Problem Statement
gc.lua fails at line 410 with weak table mode 'kv' not collecting entries after references are nil'ed.

## Fixes Applied

### 1. ✅ File Object GC Registration (COMPLETE)
- **Issue**: File Value objects weren't registered with GC due to missing interpreter reference
- **Fix**: Pass interpreter to createLuaFile() and manually register with GC
- **Result**: files.lua now 100% PASSING (all 950+ lines)
- **Files modified**: 
  - lib/src/io/lua_file.dart
  - lib/src/stdlib/lib_io.dart

### 2. ✅ Environment Nil Filtering (PARTIAL)
- **Issue**: Environment.getReferences() included Box objects with nil values
- **Fix**: Skip nil values in Environment.getReferences()
- **Result**: Simple weak table tests PASS, gc.lua still FAILS at line 410
- **Files modified**:
  - lib/src/environment.dart (line 180-181)

### 3. ✅ Box Nil Filtering (PARTIAL)  
- **Issue**: Box.getReferences() returned nil Values as GCObjects
- **Fix**: Skip nil values in Box.getReferences()
- **Result**: No observable improvement
- **Files modified**:
  - lib/src/environment.dart (line 26-27)

### 4. ✅ Do-End Block Cleanup (TESTED)
- **Issue**: Do-end block Boxes might keep values alive after scope ends
- **Fix**: Clear all Box values to null when do-end blocks complete (like loops do)
- **Result**: No observable improvement, gc.lua still fails at line 410
- **Files modified**:
  - lib/src/interpreter/control_flow.dart (line 1075-1077)

## Current Status

**Test Results**:
- ✅ files.lua: 100% PASSING
- ❌ gc.lua: FAILING at line 410 (weak tables section)
- ❌ Dart GC tests: 4 failing (down from 9)
  - weak_all_test.dart: 1 failure
  - weak_values_test.dart: 1 failure  
  - comprehensive_weak_test.dart: 1 failure
  - incremental_step_size_test.dart: 1 failure

**What Works**:
- Simple weak table tests (single scope, fresh variable names)
- Weak tables in function scope
- File GC and io.lines iteration

**What Fails**:
- gc.lua line 410 (complex multi-scope weak table test)
- Variable name reuse across scopes with weak tables
- Tests with assertion loops comparing weak table values

## Root Cause Analysis

**The Mystery**:
1. Simple tests with `local x = {}; a[1] = x; x = nil; collectgarbage()` → ✅ WORKS
2. Same test after prior `do local x = "old" end` block → ❌ FAILS
3. Loop with `local t` between blocks → ✅ FIXES IT

**Evidence**:
- Environment and Box nil filtering IS working (confirmed via logging)
- Weak table is correctly recognized as mode 'kv'
- _clearAllWeak() is being called
- But values remain marked=true when checked

**Hypothesis**: 
The empty table Value objects are being marked from some unexpected source that's not filtered by our nil checks. Possible sources:
1. Old do-end Environment objects kept in GC pool
2. Raw Map traversal of weak table storage
3. Some caching or optimization keeping references
4. CallStack frame debug locals

## Next Steps (In Order)

###  Priority 1: Isolate the Marking Source
Need to determine exactly WHERE the empty tables are being marked from during the second GC cycle.

Approach: Add minimal targeted logging to trace marking of specific table hash codes.

### Priority 2: Try Alternative Fix Strategies  
- Option A: Don't register do-end Environments with GC (only current env needs to be rooted)
- Option B: Add generation number to Environments, skip old generations in getReferences
- Option C: Clear Environment.values Map entirely when Environment goes out of scope

### Priority 3: Proceed with Upvalue Auto-Registration
This is an independent fix that will resolve 8 of the Dart test failures immediately.

### Priority 4: Compare with Working Commit
Check commit 2d6b77a (which reached line 475) to see what was different about GC traversal.

## Files Modified So Far

- ✅ lib/src/io/lua_file.dart - File GC registration
- ✅ lib/src/stdlib/lib_io.dart - IO function interpreter refs  
- ✅ lib/src/environment.dart - Nil filtering in Environment and Box
- ✅ lib/src/interpreter/control_flow.dart - Do-end block cleanup
- ✅ lib/src/gc/generational_gc.dart - Debug logging (to be cleaned up)

## OpenSpec Proposal Status

✅ Created and validated: `fix-weak-table-collection`
- 6 requirements with scenarios
- 27 implementation tasks
- Comprehensive design document

**Awaiting**: Resolution of core weak table issue before full implementation.
