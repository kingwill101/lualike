/// Flutter integration for lualike.
///
/// Provides:
/// - AssetBundle filesystem backend for `require()`, `dofile()`, `io.open()`
/// - Build hook for compiling Lua scripts at build time
///
/// ## Quick start
///
/// ```dart
/// import 'package:flutter_lualike/flutter_lualike.dart';
///
/// await useAssetBundle(rootBundle, assetRoot: 'build/lua');
/// ```
///
/// ## Build hook
///
/// ```dart
/// // hook/build.dart
/// import 'package:flutter_lualike/hooks.dart';
///
/// void main(List<String> args) async {
///   await build(args, (input, output) async {
///     final builder = LuaBuilder(sources: ['assets/lua/']);
///     await builder.run(input: input, output: output, logger: null);
///   });
/// }
/// ```
library;

export 'src/asset_bundle_backend.dart';
export 'src/asset_bundle_io_device.dart';
export 'src/config.dart';
