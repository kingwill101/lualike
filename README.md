<!--
This README describes the package. If you publish this package to pub.dev,
this README's contents appear on the landing page for your package.

For information about how to write a good package README, see the guide for
[writing package pages](https://dart.dev/tools/pub/writing-package-pages).

For general information about developing packages, see the Dart guide for
[creating packages](https://dart.dev/guides/libraries/create-packages)
and the Flutter guide for
[developing packages and plugins](https://flutter.dev/to/develop-packages).
-->

# LuaLike

A Lua-like language interpreter implemented in Dart, focusing on a clean, easy-to-use AST-based interpreter.

## Features

- Lua-like syntax and semantics
- AST-based interpreter
- Rich standard library implementation
- Seamless interoperability with Dart
- Built-in `debug` library and configurable logger
- Robust error handling with protected calls

## Getting started

Add the package to your `pubspec.yaml`:

```yaml
dependencies:
  lualike: ^0.1.0
```

## Usage

### Basic Usage

The primary way to execute code is using the AST interpreter.

```dart
import 'package:lualike/lualike.dart';

void main() async {
  // Execute some code
  final result = await executeCode('''
    local x = 10
    local y = 20
    return x + y
  ''');

  print('Result: $result');
}
```

### Dart Interoperability

You can easily bridge Dart and LuaLike code using the `LuaLike` class.
The class provides two-way interoperability:
- **`expose`**: Makes Dart functions available to be called from Lua.
- **`call`**: Allows Dart to call functions defined in Lua.

```dart
import 'package:lualike/lualike.dart';

void main() async {
  // Create a lualike instance
  final lualike = LuaLike();

  // 1. Expose a Dart function to LuaLike
  lualike.expose('dart_print', print);

  // 2. Define a Lua function that uses the exposed Dart function
  await lualike.runCode('''
    function greet_from_lua(name)
      dart_print("Hello, " .. name .. " from a Dart function!")
    end
  ''');

  // 3. Call the Lua function from Dart
  await lualike.call('greet_from_lua', [Value("World")]);

  // 4. Share data from Dart to Lua
  lualike.setGlobal('config', {'debug': true, 'maxRetries': 3});

  await lualike.runCode('''
    if config.debug then
      dart_print("Max retries: " .. config.maxRetries)
    end
  ''');
}
```

### Error Handling

LuaLike provides robust error handling through `pcall` and `xpcall` functions, which allow you to execute code in protected mode:

```dart
import 'package:lualike/lualike.dart';

void main() async {
  final lualike = LuaLike();

  // Execute code with error handling
  await lualike.runCode('''
    -- Try to execute a function that might throw an error
    local status, result = pcall(function()
      -- This will succeed
      return "success"
    end)

    print("Status:", status, "Result:", result)

    -- Try to execute a function that will throw an error
    local errorStatus, errorMsg = pcall(function()
      error("something went wrong")
    end)

    print("Error Status:", errorStatus, "Error Message:", errorMsg)
  ''');
}
```

### Logging

LuaLike includes a configurable logging system that can be useful for debugging.

```dart
import 'package:lualike/lualike.dart';

void main() async {
  // Enable logging
  Logger.setEnabled(true);

  await executeCode('''
    local x = 10
    local y = 20
    return x + y
  ''', ExecutionMode.astInterpreter);

  // Disable logging
  Logger.setEnabled(false);
}
```

When logging is enabled, you'll see detailed information about the execution process, including:
- Environment creation and variable lookups
- Variable assignments and declarations
- Function calls and returns
- Conditional evaluations
- And more

## Testing

This project includes a suite of integration tests. To run them, use the following command:


## Documentation

For more examples, check out the `/example` folder.

For detailed documentation, see the `/docs` folder, which includes guides on:
- [Value handling](./docs/guides/value_handling.md)
- [Metatables and metamethods](./docs/guides/metatables.md)
- [Error handling](./docs/guides/error_handling.md)
- [Writing builtin functions](./docs/guides/writing_builtin_functions.md)
- [Standard library implementation](./docs/guides/standard_library.md)
