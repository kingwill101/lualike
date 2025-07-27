# Garbage Collection in LuaLike

This directory contains the implementation of LuaLike's garbage collection system, which is modeled after Lua 5.4's garbage collection as described in section 2.5 of the [Lua 5.4 Reference Manual](https://www.lua.org/manual/5.4/manual.html#2.5).

## Overview

LuaLike implements a generational garbage collector that divides objects into two generations:

1. **Young Generation (Nursery)**: Contains newly created objects
2. **Old Generation**: Contains objects that have survived at least one collection cycle

The collector performs two types of collections:

- **Minor Collections**: Only traverse objects in the young generation
- **Major Collections**: Traverse all objects in both generations

## Implementation Details

### Base GC Object

All objects that need to be garbage collected must extend the `GCObject` class, which provides:

- A `marked` flag for mark-and-sweep collection
- An `isOld` flag to determine which generation the object belongs to
- A `getReferences()` method to allow traversal of the object graph
- A `free()` method for resource cleanup when collected

### Generational Collection

The `GenerationalGCManager` class implements the generational garbage collector with the following key features:

1. **Two Generations**: Objects are divided into young and old generations
2. **Promotion**: Objects that survive a minor collection are promoted to the old generation
3. **Collection Triggers**: Collections are triggered based on memory usage thresholds
4. **Tunable Parameters**: The collector's behavior can be adjusted using parameters similar to Lua's

### Finalizers

The garbage collector supports finalizers through the `__gc` metamethod, as described in section 2.5.3 of the Lua reference manual:

1. Objects with a `__gc` metamethod in their metatable are marked for finalization
2. When such objects are detected as dead, they are added to a finalization list
3. After collection, finalizers are called in reverse order of marking
4. Errors in finalizers are caught and reported but not propagated

## Tuning Parameters

The garbage collector's behavior can be adjusted using the following parameters:

- **Step Size**: Controls the size of each incremental step
- **Minor Multiplier**: Controls the frequency of minor collections (default: 100, max: 200)
- **Major Multiplier**: Controls the frequency of major collections (default: 100, max: 1000)

## Key Differences from Lua

While our implementation follows the Lua reference manual closely, there are some differences:

1. **Memory Estimation**: We use a simpler object count-based approach rather than byte counting
2. **Weak Tables**: Not fully implemented yet
3. **Resurrection Handling**: Simplified compared to Lua's implementation

## Usage

The garbage collector is automatically initialized when the interpreter is created. It can be controlled through the following methods:

```dart
// Get the GC instance
final gc = interpreter.gc;

// Stop the garbage collector
gc.stop();

// Start the garbage collector
gc.start();

// Force a collection
gc.collect(interpreter.getRoots());

// Adjust parameters
gc.minorMultiplier = 20;
gc.majorMultiplier = 200;
```

## References

- [Lua 5.4 Reference Manual - Section 2.5: Garbage Collection](https://www.lua.org/manual/5.4/manual.html#2.5)
- [Lua 5.4 Reference Manual - Section 2.5.2: Generational Garbage Collection](https://www.lua.org/manual/5.4/manual.html#2.5.2)
- [Lua 5.4 Reference Manual - Section 2.5.3: Garbage-Collection Metamethods](https://www.lua.org/manual/5.4/manual.html#2.5.3)