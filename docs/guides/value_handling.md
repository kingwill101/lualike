# Value Handling in LuaLike

This guide explains how to work with the `Value` class in the LuaLike library, which is used to represent Lua values in Dart.

## Overview

In LuaLike, all Lua values are represented by the `Value` class, which wraps Dart values and provides methods for working with them in a Lua-like way. Understanding how to properly handle `Value` objects is essential for implementing builtin functions and extending the library.

## The Value Class

The `Value` class is a wrapper around Dart values that provides methods for working with them in a Lua-like way. Here's a simplified version of the class:

```dart
class Value {
  final Object? raw;
  final Map<String, dynamic>? metatable;

  Value(this.raw, [this.metatable]);

  // Methods for working with values
  // ...
}
```

## The ValueClass Utility

LuaLike provides a `ValueClass` utility that makes it easier to create `Value` objects with predefined metatables. This is particularly useful for creating custom types with specific behavior.

```dart
class ValueClass implements BuiltinFunction {
  final Map<String, dynamic> _metatable;
  final Map<dynamic, dynamic>? _initialValues;

  ValueClass(this._metatable, [this._initialValues]);

  // Factory methods for creating common types
  static Value meta([Map<String, dynamic>? initial]) { /* ... */ }
  static Value table([Map<dynamic, dynamic>? initial]) { /* ... */ }
  static Value string(String value) { /* ... */ }
  static Value number(num value) { /* ... */ }
  static Value function(Function value) { /* ... */ }
  static Value userdata(dynamic value) { /* ... */ }

  // Create a new ValueClass with the given metamethods
  static ValueClass create(Map<String, dynamic> metamethods) {
    return ValueClass(metamethods);
  }

  // When called as a function, creates a new Value with the predefined metatable
  @override
  Object? call(List<Object?> args) {
    return Value(Map<String, dynamic>.from({}), _metatable);
  }

  get metamethods => _metatable;
}
```

### Creating Custom Types with ValueClass

You can use `ValueClass` to create custom types with specific behavior:

```dart
// Create a Point class with metamethods
final pointClass = ValueClass.create({
  "__add": (List<Object?> args) {
    final a = args[0] as Value;
    final b = args[1] as Value;
    return Value({
      "x": (a.raw["x"] as num) + (b.raw["x"] as num),
      "y": (a.raw["y"] as num) + (b.raw["y"] as num),
    });
  },
  "__tostring": (List<Object?> args) {
    final p = args[0] as Value;
    return Value("Point(${p.raw['x']}, ${p.raw['y']})");
  },
});

// Create a new Point
final point = pointClass.call([]);
point.raw["x"] = 10;
point.raw["y"] = 20;
```

### Using ValueClass Factory Methods

`ValueClass` provides factory methods for creating common types with their default metatables:

```dart
// Create a table with default table metamethods
final table = ValueClass.table({
  1: Value("first"),
  2: Value("second"),
  "key": Value("value"),
});

// Create a string with default string metamethods
final str = ValueClass.string("hello");

// Create a number with default number metamethods
final num = ValueClass.number(42);

// Create a function with default function metamethods
final func = ValueClass.function((List<Object?> args) {
  return Value("result");
});

// Create a userdata with default userdata metamethods
final userData = ValueClass.userdata(SomeCustomClass());
```

## Value Types

The `raw` field of a `Value` object can contain the following types:

- `null`: Represents Lua's `nil` value
- `bool`: Represents Lua's boolean values
- `num` (`int` or `double`): Represents Lua's number values
- `String`: Represents Lua's string values
- `Map`: Represents Lua's table values
- `Function`: Represents Lua's function values
- Other Dart objects: Represented as userdata in Lua

## Creating Value Objects

To create a `Value` object, simply pass the Dart value to the constructor:

```dart
// Create a nil value
final nilValue = Value(null);

// Create a boolean value
final boolValue = Value(true);

// Create a number value
final numValue = Value(42);

// Create a string value
final strValue = Value("hello");

// Create a table value
final tableValue = Value(<dynamic, dynamic>{
  1: Value("first"),
  2: Value("second"),
  "key": Value("value"),
});

// Create a function value
final funcValue = Value((List<Object?> args) {
  // Function implementation
  return Value("result");
});
```

## Unwrapping Values

To access the raw Dart value inside a `Value` object, use the `raw` field:

```dart
final value = Value(42);
final rawValue = value.raw; // 42
```

For convenience, you can also use the `unwrap()` method, which handles nested `Value` objects:

```dart
final value = Value(Value(42));
final unwrappedValue = value.unwrap(); // 42
```

## Type Checking

To check the type of a `Value` object, use the `is` operator on the `raw` field:

```dart
final value = Value(42);

if (value.raw is num) {
  // Handle number value
} else if (value.raw is String) {
  // Handle string value
} else if (value.raw is Map) {
  // Handle table value
} else if (value.raw is Function) {
  // Handle function value
} else if (value.raw == null) {
  // Handle nil value
}
```

## Type Conversion

Lua has automatic type conversion in some contexts. Here's how to implement similar behavior in Dart:

### Number to String Conversion

```dart
String numberToString(Value value) {
  if (value.raw is num) {
    return value.raw.toString();
  }
  throw Exception("cannot convert to string");
}
```

### String to Number Conversion

```dart
num stringToNumber(Value value) {
  if (value.raw is String) {
    final str = value.raw as String;
    final num = num.tryParse(str);
    if (num != null) {
      return num;
    }
  }
  throw Exception("cannot convert to number");
}
```

## Comparing Values

Comparing `Value` objects requires special handling to match Lua's behavior:

```dart
bool valuesEqual(Value a, Value b) {
  // Same type comparison
  if (a.raw is num && b.raw is num) {
    return (a.raw as num) == (b.raw as num);
  }
  if (a.raw is String && b.raw is String) {
    return (a.raw as String) == (b.raw as String);
  }
  if (a.raw is bool && b.raw is bool) {
    return (a.raw as bool) == (b.raw as bool);
  }
  if (a.raw == null && b.raw == null) {
    return true;
  }

  // Different types are never equal in Lua
  if (a.raw.runtimeType != b.raw.runtimeType) {
    return false;
  }

  // For tables and functions, compare references
  return identical(a.raw, b.raw);
}
```

## Working with Tables

Tables in LuaLike are represented as `Map` objects. Here's how to work with them:

```dart
// Create a table
final table = <dynamic, dynamic>{
  1: Value("first"),
  2: Value("second"),
  "key": Value("value"),
};

// Get a value from the table
final value = table[1]; // Value("first")

// Set a value in the table
table[3] = Value("third");

// Check if a key exists
final hasKey = table.containsKey("key"); // true

// Get all keys
final keys = table.keys.toList(); // [1, 2, "key", 3]

// Get all values
final values = table.values.toList(); // [Value("first"), Value("second"), Value("value"), Value("third")]
```

## Working with Functions

Functions in LuaLike can be represented in several ways:

1. As a `BuiltinFunction` implementation
2. As a Dart function that takes a list of arguments and returns a value
3. As a closure created by the interpreter

Here's how to call a function:

```dart
// Call a builtin function
final result = myBuiltinFunction.call([arg1, arg2]);

// Call a Dart function
final func = (List<Object?> args) {
  // Function implementation
  return Value("result");
};
final result = func([arg1, arg2]);

// Call a closure
final closure = value.raw as Function;
final result = await closure([arg1, arg2]);
```

## Metatables

Metatables in LuaLike are represented as `Map<String, dynamic>` objects. Here's how to work with them:

```dart
// Create a metatable
final metatable = <String, dynamic>{
  "__add": (List<Object?> args) {
    final a = args[0] as Value;
    final b = args[1] as Value;
    return Value((a.raw as num) + (b.raw as num));
  },
  "__index": (List<Object?> args) {
    final table = args[0] as Value;
    final key = args[1] as Value;
    // Implementation
  },
};

// Create a value with a metatable
final value = Value(42, metatable);

// Check if a value has a metatable
final hasMetatable = value.metatable != null;

// Get a metamethod
final addMethod = value.metatable?["__add"];
```

## Best Practices

1. **Use ValueClass for common types**: Use the `ValueClass` factory methods to create values with appropriate metatables.
2. **Create custom types with ValueClass**: Use `ValueClass.create()` to define custom types with specific behavior.
3. **Always check types**: Before accessing the `raw` field, check its type to avoid runtime errors.
4. **Wrap return values**: Always wrap return values in `Value` objects.
5. **Handle nil values**: Check for `null` values and handle them appropriately.
6. **Follow Lua semantics**: Ensure your code behaves like Lua when working with values.
7. **Use the right comparison**: Use the appropriate comparison method for the value type.
8. **Be careful with tables**: Remember that tables are reference types and can be modified.

## Common Pitfalls

1. **Forgetting to unwrap values**: Remember that `Value` objects wrap the actual Dart values.
2. **Not handling nil values**: Lua functions often have special behavior for nil values.
3. **Ignoring Lua's 1-based indexing**: Lua uses 1-based indexing, while Dart uses 0-based indexing.
4. **Not checking types**: Always check the type of a value before accessing its raw field.
5. **Comparing values incorrectly**: Use the appropriate comparison method for the value type.
6. **Not using ValueClass**: Using raw `Value` constructors instead of `ValueClass` factory methods can lead to missing metatables.

## Conclusion

Working with `Value` objects in LuaLike requires understanding how Lua values are represented in Dart and how to properly handle them. The `ValueClass` utility provides convenient methods for creating values with appropriate metatables, making it easier to implement Lua-like behavior. By following the guidelines in this document, you can write code that behaves like Lua and integrates seamlessly with the LuaLike library.