/// Re-export of `package:lualike_hooks/lualike_hooks.dart`.
///
/// Use this import in Flutter projects to access `LuaBuilder` and
/// `CompileMode` without adding `lualike_hooks` as a direct dependency.
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

export 'package:lualike_hooks/lualike_hooks.dart';
