# Writing Native Functions in Dart

This guide explains how a Dart developer can extend the `lualike` engine by writing custom "native" functions in Dart.

## Overview

You can add your own functionality to `lualike` by creating Dart classes that implement the `BuiltinFunction` interface. These functions can then be registered as global variables or added to library tables (like `string` or `math`), making them directly callable from within a `lualike` script.

This allows you to create powerful bridges between your Dart application and the `lualike` scripting environment.

## The `BuiltinFunction` Interface

The core of a native function is a Dart class that implements `BuiltinFunction`. This interface requires a single `call` method, which is what the `lualike` interpreter will execute.

```dart
import 'package:lualike/lualike.dart';

class MyNativeFunction implements BuiltinFunction {
  @override
  Object? call(List<Object?> args) {
    // Your Dart logic goes here
    return Value(null); // Return nil
  }
}
```

## Step-by-Step Guide

### Step 1: Handling Arguments

Arguments from a `lualike` script are passed to your `call` method as a `List<Object?>`. Each element in the list is typically a `Value` object, which wraps the raw `lualike` value.

It is crucial to validate the number of arguments and their types.

```dart
@override
Object? call(List<Object?> args) {
  // 1. Check argument count
  if (args.length < 2) {
    throw Exception("my_function requires at least two arguments");
  }

  // 2. Safely cast and unwrap values
  final firstArg = args[0] as Value;
  final secondArg = args[1] as Value;

  // 3. Check the underlying raw types
  if (firstArg.raw is! num || secondArg.raw is! num) {
    throw Exception("arguments must be numbers");
  }

  // 4. Use the raw values
  final num1 = firstArg.raw as num;
  final num2 = secondArg.raw as num;

  // ...
}
```

### Step 2: Returning Values

Your function must return a value that `lualike` can understand.

-   **A single value:** Wrap your return value in a `Value` object.
-   **Multiple values:** Use the `Value.multi()` factory, passing it a `List` of `Value` objects.
-   **No value (`nil`):** Return a `Value` wrapping `null`, or simply `null`.

```dart
// Return a single number
return Value(num1 + num2);

// Return multiple values
return Value.multi([Value("Success!"), Value(true)]);

// Return nil
return Value(null);
```

### Step 3: Handling Errors

To signal an error from your native function back to the `lualike` script, simply throw a Dart `Exception`. The interpreter will catch it and convert it into a `lualike` error.

```dart
if (num2 == 0) {
  throw Exception("cannot divide by zero");
}
return Value(num1 / num2);
```

### Step 4: Registering Your Function

To make your function available to scripts, you must define it in the `lualike` environment.

```dart
// Assumes 'lualike' is an instance of your interpreter bridge
final lualike = LuaLike();

// Register a global function named 'my_native_add'
lualike.env.define("my_native_add", Value(MyNativeAdd()));

// Now you can call it from a script
await lualike.runCode('''
  local result = my_native_add(10, 20)
  print(result) -- Prints: 30
''');
```

## Complete Example: A Simple `add` Function

Here is the complete code for a native `add` function.

```dart
import 'package:lualike/lualike.dart';

// The function implementation
class NativeAdd implements BuiltinFunction {
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

// How to register and use it
void main() async {
  final lualike = LuaLike();
  lualike.env.define("native_add", Value(NativeAdd()));

  await lualike.runCode('''
    local sum = native_add(5, 12)
    print("The sum is: " .. sum) -- Prints: The sum is: 17
  ''');
}
```

## Advanced Topics

### Asynchronous Functions

If your function needs to perform an async operation (like a network request or file I/O), simply make your `call` method `async` and return a `Future`. The `lualike` interpreter will automatically `await` the result.

```dart
@override
Future<Object?> call(List<Object?> args) async {
  final response = await http.get(Uri.parse('...'));
  return Value(response.body);
}
```

