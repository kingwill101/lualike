# lualike_hooks

`lualike_hooks` is the build-hook package for compiling Lua scripts as part of a Dart or Flutter build.

It supports three output strategies:

| Mode | Output | Best for |
|------|--------|----------|
| `CompileMode.bytecode` | `build/<dir>/*.lua` | simplest runtime loading, Flutter assets, Dart CLI files |
| `CompileMode.dartSource` | `build/<dir>/*.lua.dart` | generating Dart source from Lua logic |
| `CompileMode.dartEmbed` | `build/<dir>/*.lua.dart` | embedding bytecode bytes into Dart source |

## When to use which mode

- **Use `bytecode`** when you want the most straightforward setup.
  Compile at build time, ship the bytecode, and execute it with
  `LuaBytecodeRuntime`.
- **Use `dartSource`** when you want generated Dart code instead of a bytecode
  asset pipeline.
- **Use `dartEmbed`** when you want the bytecode bytes embedded as Dart
  constants (no separate asset files).

## Quick start

### 1) Add dependencies

For a Dart package:

```yaml
dependencies:
  lualike: ^0.4.0

dev_dependencies:
  lualike_hooks:
    path: path/to/lualike_hooks
  hooks: ^2.0.2
```

For Flutter, prefer [`flutter_lualike`](../flutter_lualike/README.md) which re-exports the hooks API.

### 2) Add `hook/build.dart`

```dart
import 'package:hooks/hooks.dart';
import 'package:lualike_hooks/lualike_hooks.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
    final builder = LuaBuilder(
      sources: ['lua/'],
      mode: CompileMode.bytecode,
    );
    await builder.run(input: input, output: output, logger: null);
  });
}
```

### 3) Put Lua files in your source directory

```text
your_package/
  lua/
    hello.lua
    math/util.lua
  hook/
    build.dart
  bin/
    main.dart
```

### 4) Load at runtime

```dart
import 'package:lualike/lualike.dart';

Future<void> main() async {
  final loader = LuaAssetLoader();
  final bytecode = await loader.loadBytecode('hello.lua');
  if (bytecode == null) return;

  final runtime = LuaBytecodeRuntime();
  final chunk = await runtime.loadBytecode(bytecode, moduleName: 'hello.lua');
  await runtime.callFunction(chunk, const <Object?>[]);
}
```

## Bytecode mode

This is the default mode.

### Flutter

Declare the compiled directory as an asset:

```yaml
flutter:
  assets:
    - build/lua/
```

Load the file with `rootBundle`:

```dart
import 'package:flutter/services.dart';

final data = await rootBundle.load('build/lua/hello.lua');
final bytes = data.buffer.asUint8List();
```

### Dart CLI

Use `LuaAssetLoader`:

```dart
final loader = LuaAssetLoader();
final bytes = await loader.loadBytecode('hello.lua');
```

## Dart source mode

```dart
const builder = LuaBuilder(
  sources: ['lua/'],
  mode: CompileMode.dartSource,
);
```

This mode generates `.dart` files containing lowered Lua logic as Dart code.
Use it when you want the generated source to be imported directly.

## Dart embed mode

```dart
const builder = LuaBuilder(
  sources: ['lua/'],
  mode: CompileMode.dartEmbed,
);
```

This mode generates `.dart` files containing a `List<int>` of bytecode bytes.
Use it when you want bytecode execution without separate asset files.

## Builder options

```dart
const builder = LuaBuilder(
  sources: ['lua/'],
  mode: CompileMode.bytecode,
  outputDirName: 'lua',
  enableConstantFolding: true,
  enablePeephole: true,
  stripDebug: false,
);
```

## Flutter integration

If you are building a Flutter app, the easiest path is:

1. depend on `flutter_lualike`
2. import `package:flutter_lualike/hooks.dart` in `hook/build.dart`
3. import `package:flutter_lualike/flutter_lualike.dart` at runtime

```dart
// hook/build.dart
import 'package:flutter_lualike/hooks.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
    final builder = LuaBuilder(sources: ['assets/lua/']);
    await builder.run(input: input, output: output, logger: null);
  });
}
```

```dart
// runtime
import 'package:flutter_lualike/flutter_lualike.dart';

await useAssetBundle(rootBundle, assetRoot: 'build/lua');
```

## Examples

| Example | Mode | Notes |
|---------|------|-------|
| [`examples/example_dart/`](example_dart/) | bytecode | Dart CLI end-to-end |
| [`examples/example_flutter_bytecode/`](example_flutter_bytecode/) | bytecode | Flutter assets + runtime loading |
| [`examples/example_flutter_dart_source/`](example_flutter_dart_source/) | dartSource | generated Dart source |
| [`examples/example_flutter_dart_embed/`](example_flutter_dart_embed/) | dartEmbed | embedded bytecode constant |
