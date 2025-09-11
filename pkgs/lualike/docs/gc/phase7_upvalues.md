# Phase 7: Upvalues/Closures GC Approach

## Current Implementation (Option A - Documented)

### Overview

The current lualike GC implementation treats upvalues and function bodies as **non-GC objects**. This means they are retained by Dart references rather than being managed by our custom garbage collector. This document outlines the current approach, its implications, and the rationale for this design decision.

### Current Behavior

#### Upvalue Lifecycle
- `Upvalue` objects are **not** `GCObject` instances
- They are owned by `Value` objects that represent functions/closures
- Lifetime is tied to the reachability of the containing `Value`
- Dart's own GC handles their memory management

#### Value.getReferences() Traversal
```dart
// Current implementation traverses upvalue VALUES but not upvalues themselves
if (upvalues != null) {
  for (final upvalue in upvalues!) {
    final value = upvalue.getValue();
    if (value is GCObject) {
      refs.add(value);  // Only the contained value, not the upvalue
    }
  }
}

if (functionBody != null) {
  // Function bodies (AST nodes) are NOT traversed
  // They contain no direct GC object references
}
```

#### Memory Management
- **Upvalues**: Managed by Dart GC, freed when containing `Value` is collected
- **Function Bodies**: AST nodes managed by Dart GC, no custom collection
- **Upvalue Values**: Properly traversed and marked if they are `GCObject`s

### Design Rationale

#### Why Option A (Current Approach) Was Chosen

1. **Simplicity**: Avoids complex upvalue reachability analysis
2. **Performance**: Reduces GC traversal overhead for closures
3. **Memory Footprint**: Upvalues are typically lightweight objects
4. **Dart Integration**: Leverages Dart's proven GC for non-critical objects
5. **Incremental Implementation**: Allows focus on core weak table semantics first

#### Memory Impact Analysis

**Estimated Memory per Upvalue**:
- `Upvalue` object: ~80-120 bytes
- `Box<dynamic>` reference: ~40-60 bytes  
- Metadata (name, state): ~20-40 bytes
- **Total per upvalue**: ~140-220 bytes

**Typical Usage Patterns**:
- Most functions: 0-3 upvalues
- Complex closures: 5-15 upvalues
- Memory impact: Generally <3KB per closure

### Functional Behavior

#### What Works Correctly
✅ **Upvalue Values**: Objects stored in upvalues are properly marked and preserved  
✅ **Closure Semantics**: Variable capture and access work correctly  
✅ **Nested Closures**: Multi-level closure chains function properly  
✅ **Debug Operations**: `debug.getupvalue`, `debug.setupvalue`, `debug.upvaluejoin` work  

#### Limitations
⚠️ **Upvalue Objects**: Not collectible by custom GC (rely on Dart GC)  
⚠️ **Function Bodies**: AST nodes not tracked (but typically shared/cached)  
⚠️ **Memory Accounting**: Upvalue overhead not included in `estimateMemoryUse()`  

### Lua Compatibility

#### Differences from Lua 5.4
- **Lua**: Upvalues are collectible objects with precise lifetime management
- **Lualike**: Upvalues managed by host (Dart) GC with function-scoped lifetimes

#### Behavioral Compatibility
- **Variable Access**: ✅ Identical semantics
- **Closure Scoping**: ✅ Correct behavior
- **Upvalue Joining**: ✅ `debug.upvaluejoin` works properly
- **Memory Collection**: ⚠️ Less precise timing, but functionally equivalent

### Performance Implications

#### Advantages
- **Reduced GC Pressure**: Fewer objects in custom GC tracking
- **Faster Collections**: Less traversal work during mark phase
- **Simpler Implementation**: No complex upvalue graph analysis

#### Trade-offs
- **Memory Estimation**: Less accurate memory usage reporting
- **Collection Timing**: Upvalues freed by Dart GC, not deterministic
- **Memory Fragmentation**: Potential for longer-lived upvalue objects

### Testing Coverage

Current test suite covers:
- ✅ Upvalue value traversal and preservation
- ✅ Closure functionality across GC cycles
- ✅ Complex upvalue graphs with weak tables
- ✅ Debug upvalue operations

Missing coverage:
- ⚠️ Upvalue object collection timing
- ⚠️ Memory pressure from upvalue accumulation

### Future Considerations (Option B)

If Option B is implemented in the future:

#### Changes Required
1. Make `Upvalue` extend `GCObject`
2. Update `Value.getReferences()` to include upvalue objects
3. Implement `Upvalue.getReferences()` for Box traversal
4. Add upvalue size estimation to memory accounting
5. Handle upvalue collection and resurrection semantics

#### Benefits
- More precise memory accounting
- Deterministic upvalue collection
- Closer alignment with Lua 5.4 semantics
- Better integration with weak table handling

#### Costs
- Increased GC complexity
- More objects to track and traverse
- Potential performance overhead
- Additional testing requirements

### Recommendation

**Continue with Option A** for the current implementation because:

1. **Functional Correctness**: Current approach provides correct Lua semantics
2. **Performance**: Minimal overhead for the common case
3. **Stability**: Well-tested and proven approach
4. **Incremental Development**: Can be enhanced later without breaking changes

**Consider Option B** in future if:
- Memory pressure from upvalues becomes significant
- More precise memory accounting is required
- Closer Lua compatibility is needed for specific use cases
- Performance profiling shows benefits outweigh costs

### Implementation Status

- ✅ **Phase 7A**: Current approach documented and tested
- 🔮 **Phase 7B**: Optional future enhancement for full GC integration

---

*Last Updated: September 2025*
*Implementation Status: Phase 1-6 Complete, Phase 7A Documented*