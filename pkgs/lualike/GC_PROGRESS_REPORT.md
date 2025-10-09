# GC Fixes - Final Progress Report

## Executive Summary

**Starting Point**: gc.lua failing at line 253 (files.lua test), then at line 410 (weak tables)  
**Current Status**: files.lua 100% PASSING, gc.lua still at line 410, significant GC improvements made

## ✅ Completed Fixes

### 1. File Object GC Registration ✅ 
**Problem**: File objects not registered with GC after refactoring  
**Solution**: 
- Added `interpreter` parameter to `createLuaFile()`
- Manual GC registration after setting interpreter
- Updated all IO function classes with constructors accepting interpreter

**Files Modified**:
- `lib/src/io/lua_file.dart` - createLuaFile function
- `lib/src/stdlib/lib_io.dart` - All IO and File function classes

**Impact**: **files.lua now 100% PASSING** (was failing at line 253)

### 2. Environment Nil Filtering ✅
**Problem**: Environment.getReferences() included Boxes with nil values  
**Solution**: Skip nil values in both Environment and Box getReferences()

**Files Modified**:
- `lib/src/environment.dart` lines 180-181 (Environment), lines 26-27 (Box)

**Impact**: Simple weak table tests now pass

### 3. Do-End Block Cleanup ✅
**Problem**: Do-end block Boxes might keep values alive  
**Solution**: Clear all Box values to null when blocks complete

**Files Modified**:
- `lib/src/interpreter/control_flow.dart` line 1075-1077

**Impact**: Improved cleanup, though gc.lua still fails

### 4. Upvalue Auto-Registration ✅  
**Problem**: Upvalues not automatically registered with GC  
**Solution**: 
- Added optional `interpreter` parameter to Upvalue constructor
- Auto-register in constructor if interpreter provided
- Updated all creation sites to pass interpreter

**Files Modified**:
- `lib/src/upvalue.dart` - Constructor with auto-registration
- `lib/src/stdlib/lib_base.dart` - All upvalue creation in load()
- `lib/src/interpreter/upvalue_analyzer.dart` - Upvalue analysis creation

**Impact**: **Dart test failures reduced from 9 → 5**

## 📊 Current Test Status

### Lua Tests
- ✅ **files.lua**: 100% PASSING (950+ lines)
- ❌ **gc.lua**: FAILING at line 410 (weak tables section)
  - Progress: Lines 1-409 passing
  - Blocked on: Weak table mode 'kv' collection issue

### Dart Tests  
**Before fixes**: 9 failures (all GC-related)  
**After fixes**: 5 failures

**Passing now**:
- ✅ upvalue_gc_test.dart: 5 tests (was 0/8)
- ✅ weak table basic tests

**Still failing**:
- ❌ upvalue_gc_test.dart: 3 tests (memory estimation, complex scenarios)
- ❌ weak_all_test.dart: 1 test
- ❌ comprehensive_weak_test.dart: 1 test

## 🔍 Outstanding Issues

### Issue #1: gc.lua Line 410 - Weak Table Collection
**Symptom**: Weak table with mode 'kv' doesn't collect entries after `x,y,z = nil`

**Investigation Results**:
- ✅ Environment nil filtering works (confirmed via logging)
- ✅ Box nil filtering works
- ✅ Weak table recognized correctly as mode 'kv'
- ✅ _clearAllWeak() is called
- ❌ Values still marked=true when checked

**Discovered Pattern**:
- ✓ Simple tests (fresh variable names) → PASS
- ✗ Variable name reuse across do-end blocks → FAIL
- ✓ All tests within function scope → PASS
- ✓ Test with for loop containing `local t` → PASS

**Root Cause Hypothesis**:
Empty table Value objects stored in weak tables are being marked from an unknown source during GC traversal. The issue manifests specifically when:
1. Variable names (x, y, z) are reused across scopes
2. Complex multi-scope context (like gc.lua)  
3. Assertion loops compare weak table values to local variables

**Potential Remaining Sources**:
- Old do-end Environment objects in GC pool
- CallStack frame environments or debug locals
- Some optimization/caching keeping refs

### Issue #2: Remaining Dart Test Failures
**Tests**: 
- Upvalue memory estimation tests (2)
- Upvalue complex scenario tests (1)
- Weak table metatable preservation (2)

**Likely Causes**:
- Test expectations may need adjustment for new GC architecture
- Memory estimation calculations changed with per-interpreter GC
- Some edge cases in weak table handling

## 📋 OpenSpec Proposal

**Status**: ✅ Created and validated  
**Change ID**: `fix-weak-table-collection`  
**Location**: `openspec/changes/fix-weak-table-collection/`

**Contents**:
- `proposal.md` - Problem statement, impact, scope
- `design.md` - Technical decisions, architecture changes
- `tasks.md` - 27 implementation tasks
- `specs/garbage-collection/spec.md` - 6 requirements with scenarios

**Validation**: ✅ `openspec validate fix-weak-table-collection --strict` passes

## 🎯 Recommendations

### Short Term (Unblock gc.lua)
1. **Compare GC traversal** with commit 2d6b77a that reached line 475
2. **Try reverting** do-end block Box cleanup (might be interfering)
3. **Investigate** if weak table's raw Map is being traversed directly

### Medium Term (Fix Dart Tests)
1. **Review test expectations** for memory estimation
2. **Check** if tests need updating for per-interpreter GC design
3. **Validate** weak table metatable handling

### Long Term (Complete OpenSpec)
1. Resolve gc.lua issue
2. Update proposal with final solution
3. Complete all 27 tasks
4. Archive change proposal

## 💾 Files Modified

1. ✅ `lib/src/io/lua_file.dart`
2. ✅ `lib/src/stdlib/lib_io.dart`
3. ✅ `lib/src/environment.dart`
4. ✅ `lib/src/interpreter/control_flow.dart`
5. ✅ `lib/src/upvalue.dart`
6. ✅ `lib/src/stdlib/lib_base.dart`
7. ✅ `lib/src/interpreter/upvalue_analyzer.dart`
8. ⚠️ `lib/src/gc/generational_gc.dart` (has debug logging to clean up)

## 📈 Progress Metrics

- **files.lua**: 253 → **950+ lines** (100%) ✅
- **gc.lua**: 410 lines (target: 475+, previous best: 475) 
- **Dart GC tests**: 9 failures → 5 failures (44% improvement) ✅
- **Overall test suite**: Mostly stable

## Next Session Recommendations

**Priority 1**: Compare Environment/GC traversal logic between HEAD and commit 2d6b77a  
**Priority 2**: Review weak table metatable handling  
**Priority 3**: Clean up debug logging in generational_gc.dart


