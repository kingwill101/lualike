/// Build hook for compiling Lua scripts at build time.
///
/// This package provides a build hook that automatically compiles Lua scripts
/// through the lualike pipeline. The compiled output is written to
/// `build/lua/` and can be loaded at runtime.
///
/// ## Compilation modes
///
/// [LuaBuilder] supports three compilation modes via [CompileMode]:
///
/// * **[CompileMode.bytecode]** (default) -- Compiles to Lua 5.5 bytecode
///   files. Load the bytes at runtime with `rootBundle.load()` (Flutter) or
///   `LuaAssetLoader` (Dart CLI) and execute via [LuaBytecodeRuntime].
///
/// * **[CompileMode.dartSource]** -- Compiles to standalone Dart source code
///   that embeds the IR as executable functions. Import and call directly,
///   no asset loading needed.
///
/// * **[CompileMode.dartEmbed]** -- Compiles to bytecode, then wraps the
///   bytes in a Dart file as a `List<int>` constant. Import the file and
///   pass the bytes to [LuaBytecodeRuntime].
///
/// ## Usage
///
/// 1. Add `lualike_hooks` as a dev dependency:
///
/// ```yaml
/// dev_dependencies:
///   lualike_hooks:
///     path: path/to/lualike_hooks
///   hooks: ^2.0.2
/// ```
///
/// 2. Create a `hook/build.dart` in your package:
///
/// ```dart
/// import 'package:hooks/hooks.dart';
/// import 'package:lualike_hooks/lualike_hooks.dart';
///
/// void main(List<String> args) async {
///   await build(args, (input, output) async {
///     const builder = LuaBuilder(
///       sources: ['lua/'],
///     );
///     await builder.run(input: input, output: output, logger: null);
///   });
/// }
/// ```
///
/// 3. Load and execute the compiled output at runtime:
///
/// ```dart
/// import 'package:lualike/lualike.dart';
///
/// final loader = LuaAssetLoader();
/// final bytecode = await loader.loadBytecode('hello.lua');
/// final runtime = LuaBytecodeRuntime();
/// final chunk = await runtime.loadBytecode(bytecode!, moduleName: 'hello.lua');
/// await runtime.callFunction(chunk, const <Object?>[]);
/// ```
///
/// ## Flutter
///
/// In Flutter, reference the compiled output in `pubspec.yaml`:
///
/// ```yaml
/// flutter:
///   assets:
///     - build/lua/
/// ```
///
/// Or use `flutter_lualike` for transparent asset bundle integration:
///
/// ```dart
/// import 'package:flutter_lualike/flutter_lualike.dart';
/// await useAssetBundle(rootBundle, assetRoot: 'build/lua');
/// ```
///
/// See [`example_dart/`](example_dart/) and
/// [`example_flutter/`](example_flutter/) for complete working examples.
library;

export 'src/lua_builder.dart';
