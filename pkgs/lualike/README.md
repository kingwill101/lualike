# LuaLike

[![GitHub release](https://img.shields.io/github/release/kingwill101/lualike?include_prereleases=&sort=semver&color=blue)](https://github.com/kingwill101/lualike/releases/)
[![Pub Version](https://img.shields.io/pub/v/lualike)](https://pub.dev/packages/lualike)
![GitHub Actions Workflow Status](https://img.shields.io/github/actions/workflow/status/kingwill101/lualike/.github%2Fworkflows%2Fdart.yml)
[![License](https://img.shields.io/badge/License-MIT-blue)](https://github.com/kingwill101/lualike/blob/master/LICENSE)
[![issues - lualike](https://img.shields.io/github/issues/kingwill101/lualike)](https://github.com/kingwill101/lualike/issues)

LuaLike is an embeddable Lua-like runtime and tooling package for Dart.

It includes a high-level bridge for running scripts from Dart, AST parsing APIs, low-level parser utilities, and the same standard-library registration surface used by the built-in `string`, `table`, `math`, and `debug` libraries.

## What this package exposes

- `package:lualike/lualike.dart`
  Main entrypoint for embedding LuaLike, running code, selecting an engine, parsing source into ASTs, and working with values and errors.
- `package:lualike/parsers.dart`
  Lower-level parsers for Lua format strings, binary pack formats, string parsing helpers, and Lua patterns.
- `package:lualike/library_builder.dart`
  Public extension surface for registering libraries and builder-style native APIs from Dart.

## Install

```yaml
dependencies:
  lualike: ^0.0.1-alpha.2
```

Then run:

```bash
dart pub get
```

## Quick start

```dart
import 'package:lualike/lualike.dart';

Future<void> main() async {
  final lua = LuaLike();

  lua.expose('greet', (List<Object?> args) {
    final name = args.isEmpty ? 'world' : Value.wrap(args.first).unwrap();
    return Value('Hello, $name!');
  });

  final result = await lua.execute('''
    local total = 0
    for i = 1, 4 do
      total = total + i
    end
    return greet(total)
  ''');

  print((result as Value).unwrap());
}
```

## Choose an engine

LuaLike currently ships three execution modes:

- `EngineMode.ast`
  Parses source and runs it directly with the AST interpreter.
- `EngineMode.luaBytecode`
  Emits Lua-compatible bytecode and runs it through the bytecode VM. It
  currently passes the Lua compatibility suite, but it is still slower than
  `EngineMode.ast`.
- `EngineMode.ir`
  Runs the experimental IR pipeline.

You can select an engine per call:

```dart
import 'package:lualike/lualike.dart';

Future<void> main() async {
  final astResult = await executeCode('return 20 + 22');
  final bytecodeResult = await executeCode(
    'return 20 + 22',
    mode: EngineMode.luaBytecode,
  );

  print((astResult as Value).unwrap());
  print((bytecodeResult as Value).unwrap());
}
```

Or set a process-wide default:

```dart
import 'package:lualike/lualike.dart';

void main() {
  LuaLikeConfig().defaultEngineMode = EngineMode.luaBytecode;
}
```

## Parse without executing

If you only need the syntax tree, use the exported parsing helpers instead of the runtime bridge:

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

Use `package:lualike/parsers.dart` when you want the reusable parser implementations behind helpers such as `string.format`, `string.pack`, or Lua pattern handling.

## Extend LuaLike from Dart

The simplest extension point is `LuaLike.expose()`:

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

For reusable namespaced libraries, use `package:lualike/library_builder.dart`:

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

This is the same registration path used by the built-in libraries in the repository.

## Guides and reference material

Repository guides:

- [Embedding LuaLike in Dart](https://github.com/kingwill101/lualike/blob/master/doc/guides/dart_library_usage.md)
- [Value handling](https://github.com/kingwill101/lualike/blob/master/doc/guides/value_handling.md)
- [Error handling](https://github.com/kingwill101/lualike/blob/master/doc/guides/error_handling.md)
- [Metatables and metamethods](https://github.com/kingwill101/lualike/blob/master/doc/guides/metatables.md)
- [Writing builtin functions](https://github.com/kingwill101/lualike/blob/master/doc/guides/writing_builtin_functions.md)
- [Standard library architecture](https://github.com/kingwill101/lualike/blob/master/doc/guides/standard_library.md)
- [Builder-style library pattern](https://github.com/kingwill101/lualike/blob/master/doc/guides/BUILDER_PATTERN.md)

Examples and source:

- [Dart embedding examples](https://github.com/kingwill101/lualike/tree/master/pkgs/lualike/example)
- [Standard library implementations](https://github.com/kingwill101/lualike/tree/master/pkgs/lualike/lib/src/stdlib)
- [Bytecode engine tests and examples](https://github.com/kingwill101/lualike/tree/master/pkgs/lualike/test/lua_bytecode)

## Notes on public API stability

The supported API surface is the set of symbols exported by `package:lualike/lualike.dart`, `package:lualike/parsers.dart`, and `package:lualike/library_builder.dart`.

The `lib/src/` tree is still visible in the repository for people who want to study or borrow implementations, but those files should be treated as internal details unless they are re-exported through one of the public libraries above.
