import 'dart:async' show FutureOr;

import 'package:lualike/src/runtime/lua_runtime.dart';
import 'package:lualike/src/value.dart';

/// Abstract base class representing a built-in function in the interpreter.
///
/// Built-in functions are implemented directly in Dart and provide core
/// functionality to the interpreted language. They can be called with a list
/// of arguments and return a value of any type.
abstract class BuiltinFunction {
  static final Object fastCallUnsupported = Object();

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

  /// Whether the bytecode VM may bypass managed call-stack setup for this
  /// builtin when no debug hook is active.
  bool get canBytecodeInlineWithoutManagedFrame => false;

  /// Whether this builtin is the base-library `assert` and therefore eligible
  /// for the bytecode VM's dedicated assert-success fast path.
  bool get isBytecodeAssertBuiltin => false;

  /// Optional fixed-arity fast paths used by the bytecode VM hot call sites.
  ///
  /// Returning [fastCallUnsupported] tells the caller to fall back to [call].
  Object? fastCall0() => fastCallUnsupported;

  /// Optional single-argument fast path used by hot bytecode call sites.
  Object? fastCall1(Object? arg0) => fastCallUnsupported;

  /// Optional two-argument fast path used by hot bytecode call sites.
  Object? fastCall2(Object? arg0, Object? arg1) => fastCallUnsupported;

  /// Reuses cached wrappers for primitive Lua values when the active runtime
  /// supports it, falling back to a fresh wrapper otherwise.
  Value primitiveValue(Object? raw) {
    return interpreter?.constantPrimitiveValue(raw) ?? Value(raw);
  }
}

/// Optional interface for builtins that need to keep GC-visible references.
abstract interface class BuiltinFunctionGcRefs {
  Iterable<Object?> getGcReferences();
}
