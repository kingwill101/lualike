/// An embeddable Lua-like runtime and tooling library for Dart.
///
/// This library is the main public entrypoint for embedding LuaLike in Dart
/// applications. It combines the high-level runtime bridge in `LuaLike`, the
/// one-shot execution helper `executeCode()`, AST parsing helpers such as
/// `parse()` and `parseExpression()`, and the public value and error types used
/// when Dart code exchanges data with scripts.
///
/// Typical usage starts with `LuaLike` when you want a long-lived runtime:
///
/// ```dart
/// import 'package:lualike/lualike.dart';
///
/// Future<void> main() async {
///   final lua = LuaLike();
///
///   lua.expose('double', (List<Object?> args) {
///     final value = Value.wrap(args.first).unwrap() as num;
///     return Value(value * 2);
///   });
///
///   final result = await lua.execute('return double(21)');
///   print((result as Value).unwrap());
/// }
/// ```
///
/// Use `executeCode()` when you want a one-shot helper without managing a
/// runtime instance yourself:
///
/// ```dart
/// import 'package:lualike/lualike.dart';
///
/// Future<void> main() async {
///   final result = await executeCode(
///     'return 20 + 22',
///     mode: EngineMode.luaBytecode,
///   );
///
///   print((result as Value).unwrap());
/// }
/// ```
///
/// The `EngineMode.luaBytecode` backend currently passes the Lua compatibility
/// suite, but it is still slower than the default AST interpreter in the
/// current implementation.
///
/// Use `parse()`, `parseExpression()`, `luaChunkId()`, and
/// `looksLikeLuaFilePath()` when you want syntax analysis or source labeling
/// without executing code.
///
/// For lower-level parser utilities, import `package:lualike/parsers.dart`.
/// For the native library registration APIs used by the built-in standard
/// libraries, import `package:lualike/library_builder.dart`.
library;

export 'src/ast.dart';
export 'src/builtin_function.dart';
export 'src/call_stack.dart';
export 'src/config.dart';
export 'src/environment.dart';
export 'src/error_utils.dart';
export 'src/exceptions.dart';
export 'src/executor.dart' show executeCode;
export 'src/extensions/extensions.dart';
export 'src/file_manager.dart';
export 'src/interop.dart';
export 'src/interpreter/interpreter.dart';
export 'src/logging/logging.dart';
export 'src/lua_error.dart';
export 'src/lua_stack_trace.dart';
export 'src/lua_string.dart';
export 'src/runtime/lua_runtime.dart';
export 'src/number.dart';
export 'src/number_utils.dart';
export 'src/parse.dart'
    show parse, parseExpression, luaChunkId, looksLikeLuaFilePath;
export 'src/parsers/parsers.dart';
export 'src/return_exception.dart';
export 'src/stack.dart';
export 'src/utils/platform_utils.dart';
export 'src/value.dart';
export 'src/value_class.dart';
