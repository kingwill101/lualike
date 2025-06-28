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

A Lua-like language interpreter implemented in Dart.

## Features

- Lua-like syntax and semantics
- AST-based interpreter
- Bytecode compiler and VM
- Standard library implementation
- Interoperability with Dart
- Debugging support
- Configurable logging system
- Error handling with protected calls

## Getting started

Add the package to your `pubspec.yaml`:

```yaml
dependencies:
  lualike: ^0.1.0
```

## Usage

### Basic Usage

```dart
import 'package:lualike/lualike.dart';

void main() async {
  // Execute some code
  final result = await executeCode('''
    local x = 10
    local y = 20
    return x + y
  ''', ExecutionMode.astInterpreter);

  print('Result: $result');
}
```

### Error Handling

LuaLike provides robust error handling through `pcall` and `xpcall` functions, which allow you to execute code in protected mode:

```dart
import 'package:lualike/lualike.dart';

void main() async {
  final bridge = LuaLikeBridge();

  // Execute code with error handling
  await bridge.runCode('''
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

    -- Use xpcall with a custom error handler
    local xstatus, xresult = xpcall(
      function() error("custom error") end,
      function(err) return "Handled: " .. err end
    )

    print("XPCall Status:", xstatus, "XPCall Result:", xresult)
  ''');
}
```

### Logging

LuaLike includes a configurable logging system that can be enabled or disabled globally:

```dart
import 'package:lualike/lualike.dart';

void main() async {
  // Enable logging
  Logger.setEnabled(true);

  // Execute code with logging enabled
  final result = await executeCode('''
    local x = 10
    local y = 20
    return x + y
  ''', ExecutionMode.astInterpreter);

  // Disable logging
  Logger.setEnabled(false);

  // Execute code with logging disabled
  final result2 = await executeCode('''
    local x = 30
    local y = 40
    return x + y
  ''', ExecutionMode.astInterpreter);
}
```

When logging is enabled, you'll see detailed information about the execution process, including:
- Environment creation and variable lookups
- Variable assignments and declarations
- Function calls and returns
- Conditional evaluations
- And more

This is useful for debugging and understanding how your code is being executed.

## Additional information

For more examples, check out the `/example` folder in the repository.

For detailed documentation, see the `/docs` folder, which includes guides on:
You can configure the integration tests by editing the `tools/integration.yaml` file. The configuration file includes settings for:

- Test suite path and download URL
- Execution mode (AST or bytecode)
- Logging options
- Test filters and categories
- Tests to skip
- Writing builtin functions
The integration tests can be configured through a YAML file (`tools/integration.yaml`) or through command line arguments.
- Value handling
- Metatables and metamethods
- Standard library implementation
- Error handling and protected calls
