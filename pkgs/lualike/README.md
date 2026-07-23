# LuaLike

[![GitHub release](https://img.shields.io/github/release/kingwill101/lualike?include_prereleases=&sort=semver&color=blue)](https://github.com/kingwill101/lualike/releases/)
[![Pub Version](https://img.shields.io/pub/v/lualike)](https://pub.dev/packages/lualike)
![GitHub Actions Workflow Status](https://img.shields.io/github/actions/workflow/status/kingwill101/lualike/.github%2Fworkflows%2Fdart.yml)
[![License](https://img.shields.io/badge/License-MIT-blue)](https://github.com/kingwill101/lualike/blob/master/LICENSE)
[![issues - lualike](https://img.shields.io/github/issues/kingwill101/lualike)](https://github.com/kingwill101/lualike/issues)
[![Pub Version](https://img.shields.io/pub/v/file_lualike)](https://pub.dev/packages/file_lualike)
[![Pub Version](https://img.shields.io/pub/v/process_lualike)](https://pub.dev/packages/process_lualike)

LuaLike is an embeddable **Lua 5.5-compatible** runtime and tooling package for Dart.

It provides a high-level bridge for running scripts from Dart, AST parsing APIs, parser helpers, and access to the built-in Lua standard libraries.

## CLI and Compiler

LuaLike ships as a standalone binary that can run scripts or compile them to
bytecode.

```sh
# Run a Lua script
lualike myscript.lua

# Compile to a binary chunk (--output is required; any path is fine)
lualike --compile myscript.lua -o myscript.out

# Run that binary (header-detected)
lualike myscript.out
lualike --lua-bytecode myscript.out
```

For CLI flags, compiler workflow, and advanced runtime details, see the guides
in `doc/guides/`.

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
  lualike: ^0.4.0
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

## Features

### Dart ↔ Lua interop

Expose Dart functions and call them from Lua, or call Lua functions from Dart. Share complex data structures like maps, lists, and tables between the two languages, with Lua array tables round-tripping as Dart `List`s.

```dart
lualike.expose('getCurrentTime', () => DateTime.now().toString());
lualike.expose('pow', (num x, num y) => x * y);

await lualike.execute('''
  print("2^8 =", pow(2, 8))
  print("Time:", getCurrentTime())
''');
```

See [example/interop_example.dart](example/interop_example.dart).

### Lua tables as Dart maps and lists

Lua tables are exposed as Dart `Map` objects, and array-like tables round-trip as Dart `List`s, so you can read, write, and pass them back and forth seamlessly.

```dart
// Send a config map to Lua
lua.setGlobal('config', {
  'debug': true,
  'maxRetries': 3,
});

// Read tables back from Lua
final summary = lua.getGlobal('summary')?.unwrap() as Map;
print(summary['playerLevel']);
```

This works for complex nested structures too — see [example/dart_library_example.dart](example/dart_library_example.dart).

### Error handling with pcall / xpcall

Both synchronous and asynchronous Dart functions work with Lua's `pcall` and `xpcall` error handling, including nested protected calls.

```dart
await bridge.execute('''
  local status, result = pcall(function()
    local inner, err = pcall(function()
      error("inner error")
    end)
    return inner
  end)
''');
```

See [example/error_handling_example.dart](example/error_handling_example.dart).

### Virtual file system and modules

Register virtual files so Lua's `require` can load them without a physical filesystem:

```dart
lua.fileManager.registerVirtualFile('mathutils.lua', '''
  local M = {}
  function M.factorial(n)
    if n <= 1 then return 1 end
    return n * M.factorial(n - 1)
  end
  return M
''');

await lua.execute('local m = require("mathutils"); print(m.factorial(5))');
```

See `moduleExample()` in [example/dart_library_example.dart](example/dart_library_example.dart).

### Custom I/O backend

For web platforms or testing, the `io` library's physical file backend can be
replaced with an in-memory adapter. The [web/main.dart](web/main.dart) demo
does this with `IOLib.fileSystemProvider.setIODeviceFactory()`. Check the
[`FileSystemProvider`](src/io/filesystem_provider.dart) and
[`InMemoryIODevice`](src/io/in_memory_io_device.dart) source for the pattern.

### AST parsing

Parse Lua source into an AST tree without executing it, then traverse or transform the tree.

```dart
final program = parse('''
  local answer = 42
  return answer
''', url: 'example.lua');

final expression = parseExpression('a + b * c');
print(program.statements.length);
print(expression.runtimeType);
```

See [example/lualike_example.dart](example/lualike_example.dart).

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

    // Inline documentation for IDE completion and doc generation:
    context.describe('hello', FunctionDoc(
      summary: 'Returns a greeting.',
      params: [DocParam('who', 'string', 'Name to greet.', optional: true)],
      returns: 'string',
      category: 'greeting',
    ));
  }
}

Future<void> main() async {
  final lua = LuaLike();
  lua.register(GreetingLibrary()); // shorthand for register + initialize

  final result = await lua.execute('return greeting.hello("LuaLike")');
  print((result as Value).unwrap());
}
```

This is the same registration path used by the built-in libraries in the repository. Add inline `FunctionDoc` metadata via `context.describe()` to power IDE completions and documentation generation (see [doc/guides/lsp.md](../../doc/guides/lsp.md)).

### Generate table schema docs from Dart annotations

Annotate your Dart classes with `@TableSchema()` / `@SchemaField()` and use the `table_schema` builder to auto-generate `TableDoc` constants — no manual `FieldDoc` boilerplate.

**1. Annotate a class**

```dart
import 'package:lualike/annotations.dart';

@TableSchema(description: 'Metadata table every plugin must export.')
class PluginManifest {
  @SchemaField(description: 'Unique plugin identifier.', required: true)
  final String id;

  @SchemaField(description: 'Semantic version string.', required: true)
  final String version;

  @SchemaField(
    description: 'Runtime capabilities required.',
    type: 'string[]',
    defaultValue: [],
  )
  final List<String> capabilities;
}
```

Type inference is automatic — the `List<String>` above maps to `array` unless you pass an explicit `type:` override. Supported: `String` → `string`, `int` → `integer`, `double`/`num` → `number`, `bool` → `boolean`, `List` → `array`, `Map` → `table`.

**2. Configure `build.yaml`**

```yaml
targets:
  $default:
    builders:
      lualike|table_schema:
        enabled: true
        generate_for:
          - "lib/**_schema.dart"
```

**3. Run the builder**

```sh
dart run build_runner build
```

This produces a `.table_schema.g.dart` file next to each matching source file:

```dart
// GENERATED CODE — DO NOT MODIFY BY HAND.
final pluginManifest = TableDoc(
  name: 'PluginManifest',
  description: 'Metadata table every plugin must export.',
  fields: [
    FieldDoc(key: 'id', type: 'string',
        description: 'Unique plugin identifier.', required: true),
    FieldDoc(key: 'version', type: 'string',
        description: 'Semantic version string.', required: true),
    FieldDoc(key: 'capabilities', type: 'string[]',
        description: 'Runtime capabilities required.',
        defaultValue: [], required: false),
  ],
);
```

**4. Register in your library**

```dart
class MyLibrary extends Library {
  @override
  String get name => 'my_library';

  @override
  void registerFunctions(LibraryRegistrationContext context) {
    context.describeTable('PluginManifest', pluginManifest);
  }
}
```

The annotated fields, types, defaults, and constraints are all included in the generated output and appear in both LuaLS annotations and JSON manifests. See [example/builder_demo](example/builder_demo/) for a complete walkthrough covering annotations, functions, `ValueClass`, constants, and `build_runner` automation.

## Examples

Run any example directly:

```bash
dart run example/interop_example.dart
dart run example/error_handling_example.dart
dart run example/dart_library_example.dart
dart run example/lualike_example.dart
```

| File | Demonstrates |
|------|-------------|
| [interop_example.dart](example/interop_example.dart) | Exposing Dart functions, calling Lua from Dart, sharing data |
| [error_handling_example.dart](example/error_handling_example.dart) | pcall, xpcall, async error handling, nested protected calls |
| [dart_library_example.dart](example/dart_library_example.dart) | Full-featured: basic usage, value exchange, tables, modules, config, custom functions |
| [lualike_example.dart](example/lualike_example.dart) | AST parsing: method syntax, varargs, complex source snippets |
| [builder_demo](example/builder_demo/) | Build runner integration, `@TableSchema` annotations, generated docs, and library registration |

## LSP support for your scripts

lualike generates LuaLS-compatible annotation stubs so your editor can provide
completion, hover docs, and signature help for lualike scripts — including
custom libraries you register from Dart.

### Built-in stdlib only

```sh
dart run bin/main.dart --emit-docs luals --emit-docs-output annotations.lua
```

### Your own libraries

Create `tool/generate_metadata.dart`:

```dart
import 'package:lualike/lualike.dart';
import 'package:lualike/docs.dart';
import 'package:your_project/your_project.dart';

Future<void> main() async {
  final lua = LuaLike();
  lua.vm.libraryRegistry.register(MyGameLibrary());

  await generateMetadata(
    lua,
    outputDir: 'doc/api',
    formats: {MetadataFormat.luals},
  );
}
```

Then point your LuaLS workspace library at the generated file. See
[doc/guides/lsp.md](../../doc/guides/lsp.md) for editor-specific configuration
(Neovim, VS Code, `.luarc.json`).

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

## Workspace packages

| Package | Badge | What it does |
|---|---|---|
| [`lualike`](https://pub.dev/packages/lualike) | [![Pub Version](https://img.shields.io/pub/v/lualike)](https://pub.dev/packages/lualike) | Core runtime, compiler, parser helpers, and standard-library bridge. |
| [`flutter_lualike`](https://pub.dev/packages/flutter_lualike) | [![Pub Version](https://img.shields.io/pub/v/flutter_lualike)](https://pub.dev/packages/flutter_lualike) | Flutter integration for loading Lua assets and build hooks. |
| [`file_lualike`](https://pub.dev/packages/file_lualike) | [![Pub Version](https://img.shields.io/pub/v/file_lualike)](https://pub.dev/packages/file_lualike) | Bridges `package:file` filesystems into lualike. |
| [`process_lualike`](https://pub.dev/packages/process_lualike) | [![Pub Version](https://img.shields.io/pub/v/process_lualike)](https://pub.dev/packages/process_lualike) | Bridges remote process execution into lualike. |
| [`lualike_ffi`](https://pub.dev/packages/lualike_ffi) | [![Pub Version](https://img.shields.io/pub/v/lualike_ffi)](https://pub.dev/packages/lualike_ffi) | Native FFI backend for calling trusted shared libraries. |
| [`lualike_hooks`](https://pub.dev/packages/lualike_hooks) | [![Pub Version](https://img.shields.io/pub/v/lualike_hooks)](https://pub.dev/packages/lualike_hooks) | Build hooks for compiling Lua scripts and bundling generated assets. |

The remaining workspace packages (`love2d`, `lualike_rt`, `love2d_gpu`, and `test`) are internal or support packages and are not listed here.

## Notes on public API stability

The supported API surface is the set of symbols exported by `package:lualike/lualike.dart`, `package:lualike/parsers.dart`, and `package:lualike/library_builder.dart`.

The `lib/src/` tree is still visible in the repository for people who want to study or borrow implementations, but those files should be treated as internal details unless they are re-exported through one of the public libraries above.

## More details

For deeper implementation notes and advanced workflows, see the guides in `doc/guides/` and the source tree under `pkgs/lualike/`.
