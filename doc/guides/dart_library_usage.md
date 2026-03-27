# Using LuaLike as a Dart Library

This guide explains the main public APIs for embedding LuaLike in a Dart
application.

It focuses on the supported package entrypoints:

- `package:lualike/lualike.dart`
- `package:lualike/parsers.dart`
- `package:lualike/library_builder.dart`

## Related Guides

- [Value handling](./value_handling.md)
- [Error handling](./error_handling.md)
- [Writing Native Functions in Dart](./writing_builtin_functions.md)
- [Building a Lua-like Library with Builder Interface](./BUILDER_PATTERN.md)
- [The Standard Library in LuaLike](./standard_library.md)

## Table of Contents

- [Install](#install)
- [Choose the right entrypoint](#choose-the-right-entrypoint)
- [Quick start](#quick-start)
- [Run code with a long-lived runtime](#run-code-with-a-long-lived-runtime)
- [Run code without creating a bridge](#run-code-without-creating-a-bridge)
- [Choose an execution engine](#choose-an-execution-engine)
- [Parse without executing](#parse-without-executing)
- [Exchange values with Dart](#exchange-values-with-dart)
- [Expose Dart functions](#expose-dart-functions)
- [Call LuaLike functions from Dart](#call-lualike-functions-from-dart)
- [Run files and modules](#run-files-and-modules)
- [Handle errors](#handle-errors)
- [Build reusable libraries](#build-reusable-libraries)
- [Performance notes](#performance-notes)

## Install

Add LuaLike to your `pubspec.yaml`:

```yaml
dependencies:
  lualike: ^0.0.1-alpha.2
```

Then run:

```bash
dart pub get
```

## Choose the right entrypoint

Use `package:lualike/lualike.dart` when you want to:

- create a `LuaLike` bridge
- execute code with `executeCode()`
- parse source with `parse()` or `parseExpression()`
- work with `Value`, `LuaError`, `LuaLikeConfig`, and `EngineMode`

Use `package:lualike/parsers.dart` when you want lower-level parser helpers for:

- Lua-style format strings
- binary pack and unpack formats
- string utilities
- Lua patterns

Use `package:lualike/library_builder.dart` when you want to expose reusable
libraries from Dart and need:

- `Library`
- `LibraryRegistry`
- `LibraryRegistrationContext`
- `BuiltinFunctionBuilder`

## Quick start

```dart
import 'package:lualike/lualike.dart';

Future<void> main() async {
  final lua = LuaLike();

  final result = await lua.execute('''
    local total = 0
    for i = 1, 4 do
      total = total + i
    end
    return total
  ''');

  print((result as Value).unwrap());
}
```

## Run code with a long-lived runtime

Use `LuaLike` when you want one runtime instance that keeps globals, loaded
modules, and any registered Dart functions around between executions.

```dart
import 'package:lualike/lualike.dart';

Future<void> main() async {
  final lua = LuaLike();

  lua.setGlobal('appName', 'LuaLike');

  await lua.execute('''
    greeting = "hello from " .. appName
  ''');

  final greeting = lua.getGlobal('greeting') as Value;
  print(greeting.unwrap());
}
```

## Run code without creating a bridge

Use `executeCode()` for one-shot evaluation:

```dart
import 'package:lualike/lualike.dart';

Future<void> main() async {
  final result = await executeCode('return 20 + 22');
  print((result as Value).unwrap());
}
```

This is useful for tests, utilities, and places where you do not need to keep
runtime state between calls.

## Choose an execution engine

LuaLike currently exposes three execution modes:

- `EngineMode.ast`
  Parses source and runs it directly with the AST interpreter.
- `EngineMode.luaBytecode`
  Emits Lua-compatible bytecode and runs it through the bytecode VM.
- `EngineMode.ir`
  Runs the experimental IR pipeline.

You can select the engine per call:

```dart
final result = await executeCode(
  'return 20 + 22',
  mode: EngineMode.luaBytecode,
);
```

Or set the default for `LuaLike()` and `executeCode()`:

```dart
LuaLikeConfig().defaultEngineMode = EngineMode.luaBytecode;
```

## Parse without executing

Use the parser helpers when you need syntax trees or source metadata without
creating a runtime:

```dart
import 'package:lualike/lualike.dart';

void main() {
  final program = parse('''
    local answer = 42
    return answer
  ''', url: 'example.lua');

  final expression = parseExpression('a + b * c');

  print(program.statements.length);
  print(expression.runtimeType);
  print(luaChunkId('example.lua'));
}
```

`looksLikeLuaFilePath()` is a small helper used by the runtime and diagnostics
to decide when a source label should be treated like a path.

## Exchange values with Dart

LuaLike wraps script values in `Value`. When you read globals or receive
results, unwrap them before using them as plain Dart values.

```dart
final result = await executeCode('return {name = "LuaLike", version = 1}');
final table = (result as Value).unwrap() as Map;

print((table['name'] as Value).unwrap());
print((table['version'] as Value).unwrap());
```

When you send values into the runtime, `LuaLike` wraps them automatically:

```dart
final lua = LuaLike();
lua.setGlobal('config', {
  'debug': true,
  'retries': 3,
});
```

Use `Value.wrap()` when you want the same conversion behavior in your own
extension code.

## Expose Dart functions

Use `LuaLike.expose()` to make a Dart function callable from scripts:

```dart
import 'package:lualike/lualike.dart';

Future<void> main() async {
  final lua = LuaLike();

  lua.expose('double', (List<Object?> args) {
    final value = Value.wrap(args.first).unwrap() as num;
    return Value(value * 2);
  });

  final result = await lua.execute('return double(21)');
  print((result as Value).unwrap());
}
```

The exposed function can either accept `List<Object?>` directly or accept
spread positional arguments. Returning a `Value` is the safest option when you
want precise control over what the runtime sees.

## Call LuaLike functions from Dart

Use `LuaLike.call()` after defining a function in script code:

```dart
final lua = LuaLike();

await lua.execute('''
  function greet(name)
    return "Hello, " .. name
  end
''');

final result = await lua.call('greet', [Value('world')]);
print((result as Value).unwrap());
```

## Run files and modules

Use `runFile()` when you want to execute a script file as a top-level chunk:

```dart
import 'package:lualike/lualike.dart';

Future<void> main() async {
  final results = await runFile('scripts/main.lua');
  print(results.map((value) => value.unwrap()).toList());
}
```

The runtime also tracks `_SCRIPT_PATH` and `_SCRIPT_DIR` for file-backed
execution so error messages, `require`, and debug helpers can resolve paths
consistently.

## Handle errors

Runtime and syntax failures surface as normal Dart exceptions, often as
`LuaError`.

```dart
try {
  await executeCode('return nil + 1');
} on LuaError catch (error) {
  print(error.message);
}
```

For script-level handling, use LuaLike's `pcall` and `xpcall`. For host-level
handling, use standard Dart `try` / `catch` around `executeCode()` or
`LuaLike.execute()`.

## Build reusable libraries

For one-off host integration, `expose()` is usually enough. For reusable
namespaced APIs, use `package:lualike/library_builder.dart`.

```dart
import 'package:lualike/library_builder.dart';
import 'package:lualike/lualike.dart';

class GreetingLibrary extends Library {
  @override
  String get name => 'greeting';

  @override
  void registerFunctions(LibraryRegistrationContext context) {
    final builder = BuiltinFunctionBuilder(context);

    context.define('hello', builder.create((args) {
      final who = args.isEmpty ? 'world' : Value.wrap(args.first).unwrap();
      return Value('hello, $who');
    }));
  }
}

Future<void> main() async {
  final lua = LuaLike();
  lua.vm.libraryRegistry.register(GreetingLibrary());
  lua.vm.libraryRegistry.initializeLibraryByName('greeting');

  final result = await lua.execute('return greeting.hello("LuaLike")');
  print((result as Value).unwrap());
}
```

See [Writing Native Functions in Dart](./writing_builtin_functions.md) and
[Building a Lua-like Library with Builder Interface](./BUILDER_PATTERN.md) for
the full extension patterns.

## Performance notes

- `EngineMode.ast` is currently the default and the fastest general-purpose
  backend.
- `EngineMode.luaBytecode` currently passes the Lua compatibility suite, but it
  is still slower than the AST interpreter in the current implementation.
- `EngineMode.ir` is still experimental and should be treated as a development
  pipeline rather than the recommended production default.
