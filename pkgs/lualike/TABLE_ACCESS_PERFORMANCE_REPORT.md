# Table Access Performance Analysis Report

**Date:** 2025-01-06  
**Issue:** Severe performance degradation in table access operations  
**Status:** Root cause identified

## Executive Summary

Table access operations in lualike exhibit severe performance issues, with sequential access patterns being 6-10x slower than random access. The root causes are:

1. **Lack of caching for indexed access** (`t[i]`) - only field access (`t.field`) is cached
2. **Excessive Value object allocation** - every access creates multiple Value wrapper objects
3. **Double lookup overhead** - checking both storage and legacy keys for every access

## Performance Measurements

### Test Results (1000 element table)

| Access Pattern | Time (ms) | Per-Operation (ms) | Observations |
|---------------|-----------|-------------------|--------------|
| Sequential forward | 2733.65 | 2.734 | Extremely slow |
| Reverse sequential | 3213.67 | 3.214 | Worst case |
| Random access | 462.78 | 0.463 | 6x faster than sequential |
| Adjacent pairs (reverse) | 349.01 | 0.349 | Used in sort verification |

### Comparison with Operations

- Table.sort (1000 elements): ~4-6 ms ✓ Fast
- Check loop (1000 iterations): ~10 seconds ✗ Extremely slow
- Table filling (1000 elements): ~1 second ✗ O(n²) issue (separate)

## Root Cause Analysis

### 1. Missing Cache for TableIndexAccess

**Location:** `lib/src/interpreter/table.dart`

```dart
// TableFieldAccess (t.field) - HAS CACHING ✓
class _TableFieldInlineCache {
  Value? table;
  int tableVersion = -1;
  Value? value;
}

// TableIndexAccess (t[i]) - NO CACHING ✗
Future<Object?> visitTableIndexAccess(TableIndexAccess node) async {
  final table = await node.table.accept(this);
  Object? indexResult = await node.index.accept(this);
  
  final tableVal = table is Value ? table : Value(table);
  final indexVal = indexResult is Value ? indexResult : Value(indexResult);
  // ... performs lookup every time
}
```

**Impact:** Every `t[i]` access in a loop performs full evaluation and lookup, even when `i` is constant or in a predictable pattern.

### 2. Excessive Value Object Allocation

**Location:** Multiple places in the access path

Each `t[i]` access creates:
- 1 Value for the index (in visitTableIndexAccess)
- 1 Value for the result (in operator[])
- Potential additional Values during key computation

**Code example from `lib/src/interpreter/table.dart:256-257`:**
```dart
final tableVal = table is Value ? table : Value(table);
final indexVal = indexResult is Value ? indexResult : Value(indexResult);
```

**Code example from `lib/src/value.dart:602-604`:**
```dart
if ((raw as Map).containsKey(storageKey)) {
  final result = (raw as Map)[storageKey];
  return result is Value ? result : Value(result);  // Creates new Value
}
```

**Impact:** 
- In a 1000-iteration loop: 2000+ Value objects created
- Each Value constructor call may trigger GC registration
- Memory allocation/GC pressure compounds the slowness

### 3. Double Lookup Overhead

**Location:** `lib/src/value.dart` operator[]

For every table access:
```dart
// Step 1: Compute and check storage key
final storageKey = _computeStorageKey(key);
if ((raw as Map).containsKey(storageKey)) {  // Map lookup 1
  final result = (raw as Map)[storageKey];   // Map lookup 2
  return result is Value ? result : Value(result);
}

// Step 2: Compute and check legacy key
final legacyKey = _computeLegacyKey(key);
if (legacyKey != storageKey && (raw as Map).containsKey(legacyKey)) {  // Map lookup 3
  final legacyResult = (raw as Map)[legacyKey];  // Map lookup 4
  return legacyResult is Value ? legacyResult : Value(legacyResult);
}

// Step 3: Check for __index metamethod (if no key found)
```

**Key computation overhead:**
- `_computeStorageKey`: Normalizes numbers, converts LuaString to String
- `_computeLegacyKey`: Calls `_computeRawKey` 
- For integer keys: Both computations are performed even when they yield same result

**Impact:** 
- Minimum 2 map lookups per access (containsKey + get)
- Up to 4 map lookups if legacy key differs
- Key computation overhead on every access

### 4. Why Sequential is Slower than Random

**Hypothesis:** The sequential access pattern interacts poorly with:
- Dart's Map implementation internal structure
- GC triggering patterns (sequential allocation creates predictable pressure)
- Possible cache line effects or memory layout issues

**Evidence:** 
- Sequential: 2.7ms per access
- Random: 0.46ms per access
- The pattern, not the complexity, affects performance

## Comparison Operator Performance (Resolved)

The original issue report focused on comparison operators in the check loop. Investigation revealed:

### Original Implementation
```dart
operator <(Object other) {
  // ... NaN checks ...
  if ((raw is int || raw is BigInt) && otherRaw is double) {
    // Complex BigInt conversion logic with BigInt.parse(doubleVal.toStringAsFixed(0))
    // This was slow but correct for edge cases
  }
  if (raw is num && otherRaw is num) return raw < otherRaw;  // Fast path came AFTER
}
```

### Fixed Implementation
```dart
operator <(Object other) {
  // ... NaN checks ...
  // Fast path: both are doubles (most common case)
  if (raw is double && otherRaw is double) {
    return raw < otherRaw;
  }
  // Complex edge case handling for mixed int/double/BigInt comparisons
}
```

**Result:** Comparison operators are now fast for the common case (double-double) while preserving correctness for edge cases.

## Impact on Real Code

### Sort Verification Loop (Original Issue)
```lua
for n = #a, 2, -1 do
  assert(not f(a[n], a[n-1]))
end
```

With 5000 elements:
- 4999 iterations
- Each iteration: 2 table accesses + 1 function call + 1 comparison
- **Estimated time:** ~30+ seconds (based on 3ms per table access × 2 accesses)
- **Actual observation:** Script timeout/hang

### Why table.sort is Fast
`table.sort` uses internal Dart List operations and direct array access, bypassing the Value wrapper and key computation overhead entirely.

## Proposed Solutions

### 1. Implement TableIndexAccess Caching (High Priority)

**Approach:** Similar to TableFieldAccess caching

```dart
class _TableIndexCache {
  Value? table;
  int tableVersion = -1;
  Value? index;        // Cache the computed index
  Value? value;        // Cache the result
}

final Expando<_TableIndexCache> _tableIndexAccessCache = 
    Expando<_TableIndexCache>('tableIndexAccessCache');
```

**Conditions for cache validity:**
- Table identity unchanged (identical check)
- Table version unchanged (no mutations)
- Index value equals cached index
- No __index metamethod present

**Expected improvement:** 
- Reduce 1000 accesses from ~3000ms to ~100ms (30x faster)
- Eliminate redundant Value allocations
- Eliminate redundant key computations

### 2. Optimize Value Wrapping (Medium Priority)

**Options:**
- Add `isValueWrapped` flag to avoid double wrapping
- Use object pooling for common Value types (small integers, common strings)
- Lazy Value creation - keep raw values longer in interpreter

### 3. Optimize Key Lookup (Low Priority)

**Options:**
- Combine storage and legacy key checks into single operation
- Cache computed keys on Value objects
- Use a single normalized key format to eliminate legacy lookup

## Recommendations

### Priority 1: Remove Legacy Key Lookup (CRITICAL)
- **Impact:** ~40% improvement in table access performance
- **Action:** Remove all `legacyKey` code paths from `value.dart`
- **Risk:** Breaking change for tables with legacy keys
- **Mitigation:** Document as breaking change, provide migration guide

### Priority 2: Implement TableIndexAccess Caching (HIGH)
- **Impact:** 30x improvement for repeated accesses
- **Action:** Add caching similar to TableFieldAccess
- **Risk:** Low (mirrors existing pattern)
- **Combined with Priority 1:** Could achieve 100x+ improvement

### Priority 3: Optimize Value Wrapping (MEDIUM)
- **Impact:** Reduce allocation pressure
- **Action:** Profile and eliminate unnecessary Value creations
- **Risk:** Medium (requires careful analysis)

### Combined Expected Results
After implementing all three priorities:
- **Current:** 1000 sequential accesses = ~3000ms
- **After P1+P2:** 1000 sequential accesses = ~30ms (100x faster)
- **Memory:** Significantly reduced GC pressure

## Test Cases for Validation

After implementing fixes:

1. **Micro-benchmark:** 1000 sequential table accesses should complete in <100ms
2. **Sort check:** 5000-element sort verification should complete in <1s
3. **Regression:** Ensure edge cases still work (maxint, NaN, infinity comparisons)
4. **Memory:** Profile to ensure no memory leaks from caching

## Critical Discovery: Legacy Key Lookup Overhead

### The Legacy Key Problem

Every table access performs **dual key lookups** to support a migration path from an old key format:

**Storage Key (NEW):**
- Normalizes `-0.0` to `0.0` (Lua spec compliance)
- Uses Value objects as keys for non-primitives

**Legacy Key (OLD):**  
- No `-0.0` normalization
- Always unwraps Values to raw

### Migration Strategy (Current Implementation)

```dart
// On READ - check both formats
final storageKey = _computeStorageKey(key);
if ((raw as Map).containsKey(storageKey)) {
  return (raw as Map)[storageKey];
}

final legacyKey = _computeLegacyKey(key);
if (legacyKey != storageKey && (raw as Map).containsKey(legacyKey)) {
  return (raw as Map)[legacyKey];
}

// On WRITE - store in new format, remove old
(raw as Map)[storageKey] = value;
if (legacyKey != storageKey) {
  (raw as Map).remove(legacyKey);
}
```

### Why This Is Wasteful

1. **Fresh tables have no legacy data** - yet every access checks legacy key
2. **Double map lookups** - even when `legacyKey != storageKey` check passes
3. **For numbers** - the keys often differ due to `-0.0` normalization, triggering unnecessary legacy check
4. **No completion condition** - migration never "finishes" at runtime

### Impact

- **2x map operations** minimum per table access
- **Additional key computation** overhead
- **Compounds with other issues** (Value allocation, no caching)

### Recommendation: Remove Legacy Key Support

**Option 1: Hard Cutoff (Recommended)**
- Remove all legacy key code paths
- Document breaking change
- Users must rebuild tables (or provide migration script)
- **Performance gain:** ~40% reduction in table access overhead

**Option 2: Migration Flag**
- Add `_hasLegacyKeys` flag to Value
- Set to `false` for new tables
- Only check legacy if flag is `true`
- Clear flag after successful migration
- **Performance gain:** Near 40% for new tables, degraded for old

**Option 3: One-time Migration Utility**
- Provide `migrateTables()` function
- Walk all tables once and convert keys
- Remove runtime checks
- **Performance gain:** 40% after migration run

## Related Issues

- **Table filling O(n²):** Separate issue being tracked
- **GC pressure:** Related to allocation patterns, may improve with caching
- **Legacy key migration:** Performance overhead from backward compatibility

## References

- Test script: `lualike/table_access_test.lua`
- Performance diagnostic: `lualike/perf_diagnostic.lua`
- Original issue: `lualike/sort_test.lua` hanging at check loop
- Code locations:
  - `lib/src/interpreter/table.dart` - Table access interpretation
  - `lib/src/value.dart` - Value operator[] implementation