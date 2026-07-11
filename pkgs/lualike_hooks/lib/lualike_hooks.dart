/// Build hook for compiling Lua scripts to bytecode.
///
/// This package provides a build hook that automatically compiles Lua scripts
/// to bytecode. The compiled output is written to `build/lua/` and can be
/// loaded at runtime using `LuaAssetLoader` from the `lualike` package.
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
/// 3. Load and execute the compiled bytecode at runtime:
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
library;

export 'src/lua_builder.dart';
