# Writing Builtin Functions in LuaLike

This guide explains how to implement builtin functions for the LuaLike library, which is a Lua implementation in Dart.

## Overview

Builtin functions in LuaLike are implemented as Dart classes that implement the `BuiltinFunction` interface. These functions can be added to the global environment or to specific libraries like `string`, `table`, or `math`.

## The BuiltinFunction Interface

All builtin functions must implement the `BuiltinFunction` interface, which requires a `call` method:

```dart
class MyFunction implements BuiltinFunction {
  @override
  Object? call(List<Object?> args) {
    // Implementation goes here
    return Value(result);
  }
}
```

## Handling Arguments

Arguments are passed to the `call` method as a list of `Object?`. In most cases, these will be `Value` objects, but you should always check and handle different types appropriately:

```dart
Object? call(List<Object?> args) {
  if (args.isEmpty) {
    throw Exception("function requires at least one argument");
  }

  final firstArg = args[0];
  if (firstArg is! Value) {
    throw Exception("expected a Value object");
  }

  // Now you can safely use firstArg as a Value
  final value = firstArg.raw;
  // ...
}
```

## Return Values

Builtin functions should return one of the following:

1. A `Value` object
2. A `List<Object?>` for multiple return values
3. `null` for no return value

For example:

```dart
// Return a single value
return Value(42);

// Return multiple values
return [Value("hello"), Value(123)];

// Return nothing
return Value(null);
```

## Async Functions

If your function needs to perform asynchronous operations, you can make the `call` method async:

```dart
@override
Future<Object?> call(List<Object?> args) async {
  // Async implementation
  return Value(result);
}
```

## Error Handling

When an error occurs, throw an exception with a clear error message:

```dart
if (condition) {
  throw Exception("clear error message");
}
```

The interpreter will catch these exceptions and convert them to Lua errors.

## Example: Implementing a Simple Function

Here's an example of a simple function that adds two numbers:

```dart
class Add implements BuiltinFunction {
  @override
  Object? call(List<Object?> args) {
    if (args.length < 2) {
      throw Exception("add requires two arguments");
    }

    final a = args[0] as Value;
    final b = args[1] as Value;

    if (a.raw is! num || b.raw is! num) {
      throw Exception("add requires numeric arguments");
    }

    return Value((a.raw as num) + (b.raw as num));
  }
}
```

## Example: Table Library Function

Here's an example from the table library that shows how to implement a more complex function:

```dart
class _TableSort implements BuiltinFunction {
  @override
  Object? call(List<Object?> args) async {
    if (args.isEmpty) {
      throw Exception("table.sort requires a table argument");
    }

    final table = args[0] as Value;
    if (table.raw is! Map) {
      throw Exception("table.sort requires a table as first argument");
    }

    final map = table.raw as Map;
    final comp = args.length > 1 ? args[1] : null;

    // Get the array part of the table (numeric indices)
    final keys = map.keys.where((k) => k is int && k >= 1).toList()..sort();
    if (keys.isEmpty) return Value(null);

    // Implementation details...

    return Value(null);
  }
}
```

## Registering Builtin Functions

To make your builtin function available in Lua code, you need to register it in the environment:

```dart
// Register a global function
env.define("myfunc", Value(MyFunction()));

// Register a function in a library
final myLib = <String, dynamic>{
  "func1": MyFunction1(),
  "func2": MyFunction2(),
};
env.define("mylib", Value(myLib));
```

## Best Practices

1. **Validate arguments**: Always check the number and types of arguments.
2. **Clear error messages**: Provide clear error messages that match Lua's error format.
3. **Handle edge cases**: Consider all possible inputs, including nil values and incorrect types.
4. **Follow Lua semantics**: Ensure your function behaves like its Lua counterpart.
5. **Document your function**: Add comments explaining what the function does and any special behavior.
6. **Write tests**: Create tests that verify your function works correctly.

## Common Pitfalls

1. **Not unwrapping Values**: Remember that arguments are usually `Value` objects that wrap the actual Dart values.
2. **Forgetting to wrap return values**: Return values should be wrapped in `Value` objects.
3. **Not handling nil values**: Lua functions often have special behavior for nil values.
4. **Ignoring Lua's 1-based indexing**: Lua uses 1-based indexing, while Dart uses 0-based indexing.
5. **Not handling async correctly**: If your function is async, make sure to await all async operations.

## Conclusion

Writing builtin functions for LuaLike involves implementing the `BuiltinFunction` interface and handling arguments and return values correctly. By following the guidelines in this document, you can create functions that behave like their Lua counterparts and integrate seamlessly with the LuaLike library.