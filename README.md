# LuaLike

[![GitHub release](https://img.shields.io/github/release/kingwill101/lualike?include_prereleases=&sort=semver&color=blue)](https://github.com/kingwill101/lualike/releases/)
[![Pub Version](https://img.shields.io/pub/v/lualike)](https://pub.dev/packages/lualike)
![GitHub Actions Workflow Status](https://img.shields.io/github/actions/workflow/status/kingwill101/lualike/.github%2Fworkflows%2Fdart.yml)
[![License](https://img.shields.io/badge/License-MIT-blue)](#license)
[![issues - lualike](https://img.shields.io/github/issues/kingwill101/lualike)](https://github.com/kingwill101/lualike/issues)


A Lua-like language interpreter implemented in Dart, focusing on a clean, easy-to-use AST-based interpreter.

## Features

- Lua-like syntax and semantics
- AST-based interpreter
- Rich standard library implementation
- Seamless interoperability with Dart
- Robust error handling with protected calls

## Getting started

Add the package to your `pubspec.yaml`:

```yaml
dependencies:
  lualike: ^0.0.1
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

  print('Result: ${result.unwrap()}');
}
```
> Result: 30

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
  lualike.expose('dart_print', (v) {
    print("---------------");
    print(v[0].unwrap());
    print("---------------");
  });

  // 2. Define a Lua function that uses the exposed Dart function
  await lualike.execute('''
    function greet_from_lua(name)
      dart_print("Hello, " .. name .. " from a Dart function!")
    end
  ''');

  // 3. Call the Lua function from Dart
  await lualike.call('greet_from_lua', [Value("World")]);

  // 4. Share data from Dart to Lua
  lualike.setGlobal('config', {'debug': true, 'maxRetries': 3});

  await lualike.execute('''
    if config.debug then
      dart_print("Max retries: " .. config.maxRetries)
    end
  ''');
}

```

```
---------------
Hello, World from a Dart function!
---------------
---------------
Max retries: 3
---------------

```


## Documentation

For more examples, check out the `/example` folder.

For detailed documentation, see the `/docs` folder, which includes guides on:
- [Value handling](doc/guides/value_handling.md)
- [Metatables and metamethods](doc/guides/metatables.md)
- [Error handling](doc/guides/error_handling.md)
- [Writing builtin functions](doc/guides/writing_builtin_functions.md)
- [Standard library implementation](doc/guides/standard_library.md)
