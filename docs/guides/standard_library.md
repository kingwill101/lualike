# Standard Library Implementation in LuaLike

This guide explains how to implement standard library functions for the LuaLike library, focusing on compatibility with Lua's behavior.

## Overview

The standard library in LuaLike consists of several modules that provide common functionality, such as string manipulation, table operations, and mathematical functions. Implementing these functions correctly is essential for ensuring compatibility with Lua code.

## Standard Library Modules

LuaLike implements the following standard library modules:

- `string`: String manipulation functions
- `table`: Table manipulation functions
- `math`: Mathematical functions
- `os`: Operating system functions
- `io`: Input/output functions
- `utf8`: UTF-8 string manipulation functions
- `coroutine`: Coroutine functions
- `debug`: Debugging functions
- `package`: Module loading functions

Each module is implemented as a separate Dart file in the `lib/src/stdlib` directory.

## Module Structure

Each standard library module follows a similar structure:

```dart
import 'package:lualike/src/bytecode/vm.dart';
import 'package:lualike/lualike.dart';
import 'package:lualike/src/vm.dart';

import '../value_class.dart';

class ModuleNameLib {
  static final ValueClass moduleNameClass = ValueClass.create({
    // Metamethods for the module
  });

  static final Map<String, BuiltinFunction> functions = {
    "function1": _ModuleNameFunction1(),
    "function2": _ModuleNameFunction2(),
    // More functions...
  };
}

class _ModuleNameFunction1 implements BuiltinFunction {
  @override
  Object? call(List<Object?> args) {
    // Implementation
  }
}

class _ModuleNameFunction2 implements BuiltinFunction {
  @override
  Object? call(List<Object?> args) {
    // Implementation
  }
}

// More function implementations...

void defineModuleNameLibrary({
  required Environment env,
  Interpreter? astVm,
  BytecodeVM? bytecodeVm,
}) {
  final moduleTable = <String, dynamic>{};
  ModuleNameLib.functions.forEach((key, value) {
    moduleTable[key] = value;
  });
  env.define("modulename", Value(moduleTable, ModuleNameLib.moduleNameClass.metamethods));
}
```

## Implementing Standard Library Functions

When implementing standard library functions, it's important to follow Lua's behavior as closely as possible. Here are some guidelines:

### 1. Check the Lua Documentation

Before implementing a function, check the [Lua 5.4 Reference Manual](https://www.lua.org/manual/5.4/) to understand its behavior, including:

- Expected arguments and their types
- Return values
- Error handling
- Edge cases

### 2. Handle Arguments Correctly

Lua functions often have optional arguments or special behavior for certain argument types. Make sure to handle these correctly:

```dart
Object? call(List<Object?> args) {
  if (args.isEmpty) {
    throw Exception("function requires at least one argument");
  }

  final arg1 = args[0] as Value;
  final arg2 = args.length > 1 ? args[1] as Value : Value(null);
  final arg3 = args.length > 2 ? (args[2] as Value).raw as int : 0;

  // Implementation
}
```

### 3. Follow Lua's 1-Based Indexing

Lua uses 1-based indexing for strings and tables, while Dart uses 0-based indexing. Make sure to adjust indices accordingly:

```dart
// Convert from Lua's 1-based indexing to Dart's 0-based indexing
final luaIndex = (args[1] as Value).raw as int;
final dartIndex = luaIndex - 1;

// Convert from Dart's 0-based indexing to Lua's 1-based indexing
final dartIndex = str.indexOf(substr);
final luaIndex = dartIndex + 1;
```

### 4. Handle Nil Values

Lua functions often have special behavior for nil values. Make sure to handle these correctly:

```dart
final arg = args.length > 1 ? args[1] : Value(null);
if (arg.raw == null) {
  // Handle nil value
} else {
  // Handle non-nil value
}
```

### 5. Return Values Correctly

Lua functions can return multiple values. Make sure to return them correctly:

```dart
// Return a single value
return Value(result);

// Return multiple values
return [Value(result1), Value(result2), Value(result3)];

// Return no value
return Value(null);
```

### 6. Handle Errors

Lua functions throw errors with descriptive messages. Make sure to handle errors correctly:

```dart
if (condition) {
  throw Exception("descriptive error message");
}
```

## Example: Implementing a String Function

Here's an example of implementing the `string.find` function:

```dart
class _StringFind implements BuiltinFunction {
  @override
  Object? call(List<Object?> args) {
    if (args.length < 2) {
      throw Exception("string.find requires at least 2 arguments");
    }

    final str = (args[0] as Value).raw.toString();
    final pattern = (args[1] as Value).raw.toString();
    final init = args.length > 2 ? (args[2] as Value).raw as int : 1;
    final plain = args.length > 3 ? (args[3] as Value).raw as bool : false;

    // Adjust for Lua's 1-based indexing
    final startIndex = init > 0 ? init - 1 : str.length + init;

    if (plain) {
      // Plain string search
      final index = str.indexOf(pattern, startIndex);
      if (index == -1) {
        return Value(null);
      }
      return [Value(index + 1), Value(index + pattern.length)];
    } else {
      // Pattern matching (simplified for this example)
      final regex = RegExp(pattern);
      final match = regex.firstMatch(str.substring(startIndex));
      if (match == null) {
        return Value(null);
      }
      return [
        Value(match.start + startIndex + 1),
        Value(match.end + startIndex),
      ];
    }
  }
}
```

## Example: Implementing a Table Function

Here's an example of implementing the `table.sort` function:

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

    // Get the maximum array index
    final maxIndex = keys.last as int;

    // Create a list of values to sort
    final values = <dynamic>[];
    for (var i = 1; i <= maxIndex; i++) {
      final value = map[i];
      if (value != null) {
        values.add(value);
      }
    }

    // Sort the values
    if (comp != null) {
      // Use bubble sort for custom comparator
      for (var i = 0; i < values.length; i++) {
        for (var j = 0; j < values.length - i - 1; j++) {
          try {
            if (comp is Value && comp.raw is Function) {
              final func = comp.raw as Function;
              final a = values[j];
              final b = values[j + 1];

              // Call the comparator with values[j] and values[j+1]
              // In Lua, the comparator returns true when a should come before b
              final result = await func([a, b]);

              // If result is true, a should come before b (no swap needed)
              // If result is false, b should come before a (swap needed)
              bool shouldSwap = false;

              if (result is Value) {
                // If the result is a Value, check its raw value
                shouldSwap = result.raw != true;
              } else {
                // If the result is not a Value, check if it's truthy
                shouldSwap = result != true;
              }

              if (shouldSwap) {
                // Swap values
                final temp = values[j];
                values[j] = values[j + 1];
                values[j + 1] = temp;
              }
            } else {
              throw Exception("invalid order function for sorting");
            }
          } catch (e) {
            throw Exception("invalid order function for sorting: $e");
          }
        }
      }
    } else {
      // Default comparison
      values.sort((a, b) {
        if (a == null) return 1;
        if (b == null) return -1;

        if (a is Value && b is Value) {
          final aVal = a.raw;
          final bVal = b.raw;

          // Both numbers
          if (aVal is num && bVal is num) {
            return aVal.compareTo(bVal);
          }

          // Both strings
          if (aVal is String && bVal is String) {
            return aVal.compareTo(bVal);
          }

          // Mixed types or unsupported types
          throw Exception("attempt to compare incompatible types");
        } else if (a is num && b is num) {
          return a.compareTo(b);
        } else if (a is String && b is String) {
          return a.compareTo(b);
        } else {
          throw Exception("attempt to compare incompatible types");
        }
      });
    }

    // Update the table with sorted values
    for (var i = 0; i < values.length; i++) {
      map[i + 1] = values[i];
    }

    return Value(null);
  }
}
```

## Testing Standard Library Functions

It's important to test standard library functions to ensure they behave like their Lua counterparts. Here's an example of testing the `table.sort` function:

```dart
test('table.sort with custom comparator', () async {
  final bridge = LuaLikeBridge();

  try {
    await bridge.runCode('''
      local t = {3, 1, 4, 2, 5}
      -- In Lua, the comparator returns true when a should come before b
      -- So for descending order, we return true when a > b
      table.sort(t, function(a, b) return a > b end)
      return t[1], t[2], t[3], t[4], t[5]
    ''');
  } on ReturnException catch (e) {
    var results = e.value as List;
    expect((results[0] as Value).raw, equals(5));
    expect((results[1] as Value).raw, equals(4));
    expect((results[2] as Value).raw, equals(3));
    expect((results[3] as Value).raw, equals(2));
    expect((results[4] as Value).raw, equals(1));
  }
});
```

## Common Pitfalls

1. **Not following Lua's behavior**: Make sure to check the Lua documentation and test your implementation against Lua's behavior.
2. **Ignoring Lua's 1-based indexing**: Lua uses 1-based indexing, while Dart uses 0-based indexing.
3. **Not handling nil values**: Lua functions often have special behavior for nil values.
4. **Not handling errors correctly**: Lua functions throw errors with descriptive messages.
5. **Not handling multiple return values**: Lua functions can return multiple values.
6. **Not handling optional arguments**: Lua functions often have optional arguments.
7. **Not handling special cases**: Lua functions often have special behavior for certain inputs.

## Conclusion

Implementing standard library functions for LuaLike requires careful attention to Lua's behavior and semantics. By following the guidelines in this document, you can create functions that behave like their Lua counterparts and ensure compatibility with Lua code.