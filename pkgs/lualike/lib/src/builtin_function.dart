import 'dart:async' show FutureOr;

import 'package:lualike/src/runtime/lua_runtime.dart';

/// Abstract base class representing a built-in function in the interpreter.
///
/// Built-in functions are implemented directly in Dart and provide core
/// functionality to the interpreted language. They can be called with a list
/// of arguments and return a value of any type.
abstract class BuiltinFunction {
  /// The interpreter instance that this builtin function belongs to.
  /// This is optional for backwards compatibility with existing functions.
  final LuaRuntime? interpreter;

  /// Creates a builtin function with optional interpreter reference.
  BuiltinFunction([this.interpreter]);

  /// Executes the built-in function with the given arguments.
  ///
  /// [args] - The list of arguments passed to the function.
  /// Returns the result of the function call, which may be null.
  FutureOr<Object?> call(List<Object?> args);
}

/// Optional interface for builtins that need to keep GC-visible references.
abstract interface class BuiltinFunctionGcRefs {
  Iterable<Object?> getGcReferences();
}
