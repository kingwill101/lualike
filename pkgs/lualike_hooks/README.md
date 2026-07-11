# lualike_hooks

Build hook for compiling Lua scripts to bytecode at build time.

Scans your `lua/` directories, compiles every `.lua` file to Lua 5.5 bytecode,
and writes the compiled output to `build/lua/` so it can be loaded at runtime.

## Quick start

### 1. Add dependencies

```yaml
dependencies:
  lualike:
    path: path/to/lualike

dev_dependencies:
  lualike_hooks:
    path: path/to/lualike_hooks
  hooks: ^2.0.2
```

### 2. Create `hook/build.dart`

```dart
import 'package:hooks/hooks.dart';
import 'package:lualike_hooks/lualike_hooks.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
    const builder = LuaBuilder(
      sources: ['lua/'],
    );
    await builder.run(input: input, output: output, logger: null);
  });
}
```

### 3. Place Lua scripts

```
your_package/
  lua/
    hello.lua
    utils/math.lua
  hook/
    build.dart
  bin/
    main.dart
```

### 4. Load and execute at runtime

```dart
import 'package:lualike/lualike.dart';

void main() async {
  final loader = LuaAssetLoader();
  final bytecode = await loader.loadBytecode('hello.lua');

  if (bytecode == null) {
    print('Run "dart run" to compile Lua scripts first.');
    return;
  }

  final runtime = LuaBytecodeRuntime();
  final chunk = await runtime.loadBytecode(bytecode, moduleName: 'hello.lua');
  await runtime.callFunction(chunk, const <Object?>[]);
}
```

Or use the `LuaLike` facade for a simpler API:

```dart
import 'package:lualike/lualike.dart';

void main() async {
  // Compile source to bytecode
  final lua = await LuaLike.compile('return 1 + 2');
  
  // The bytecode is pre-loaded; execute to run top-level code
  await lua.execute('');
  
  // Or call specific functions
  final result = await lua.call('add', [1, 2]);
}
```

## How it works

1. **Build time** -- `dart run` or `flutter run` triggers `hook/build.dart`.
   `LuaBuilder` reads every `.lua` file under the configured `sources`
   directories, compiles it through the lualike pipeline (constant folding,
   peephole optimization), and writes the bytecode to `build/lua/`.

2. **Runtime** -- `LuaAssetLoader` (from the `lualike` package) reads the
   compiled files from `build/lua/`. `LuaBytecodeRuntime` executes the
   bytecode directly, skipping parsing and compilation.

## LuaBuilder options

```dart
const builder = LuaBuilder(
  // Directories to scan (relative to package root)
  sources: ['lua/', 'scripts/'],

  // Output directory name under build/
  outputDirName: 'lua',

  // Compiler optimizations
  enableConstantFolding: true,
  enablePeephole: true,

  // Strip debug info for smaller output
  stripDebug: false,
);
```

## Flutter

In Flutter apps, reference the compiled output in `pubspec.yaml`:

```yaml
flutter:
  assets:
    - build/lua/
```

Load at runtime with `rootBundle`:

```dart
import 'package:flutter/services.dart';

final data = await rootBundle.load('build/lua/app.lua');
final bytecode = data.buffer.asUint8List();
```

## Example

See [`example_dart/`](example_dart/) for a minimal Dart CLI demo.
