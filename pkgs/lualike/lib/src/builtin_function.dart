import 'dart:async' show FutureOr;

import 'package:lualike/src/runtime/lua_slot.dart';
import 'package:lualike/src/runtime/lua_runtime.dart';
import 'package:lualike/src/stdlib/doc.dart';
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

  /// Optional documentation metadata for auto-generated library docs.
  ///
  /// Override this in concrete subclasses to provide function descriptions,
  /// parameter docs, return-value notes, and code examples.  When `null` the
  /// function is still included in generated output (by name and signature)
  /// but without descriptive text.
  FunctionDoc? get doc => null;

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

  /// Whether this builtin is `debug.getlocal` for bytecode-local fast paths.
  bool get isBytecodeDebugGetLocalBuiltin => false;

  /// Whether this builtin is `debug.setlocal` for bytecode-local fast paths.
  bool get isBytecodeDebugSetLocalBuiltin => false;

  /// Whether this builtin is `pcall` for bytecode protected-call fast paths.
  bool get isBytecodeProtectedCallBuiltin => false;

  /// Optional fixed-arity fast paths used by the bytecode VM hot call sites.
  ///
  /// Returning [fastCallUnsupported] tells the caller to fall back to [call].
  Object? fastCall0() => fastCallUnsupported;

  /// Optional single-argument fast path used by hot bytecode call sites.
  Object? fastCall1(Object? arg0) => fastCallUnsupported;

  /// Optional two-argument fast path used by hot bytecode call sites.
  Object? fastCall2(Object? arg0, Object? arg1) => fastCallUnsupported;

  /// Wraps a raw primitive value in a transient [Value] without creating a
  /// permanent cache entry. This avoids the HashMap overhead in
  /// [Interpreter.constantPrimitiveValue] for builtin results (e.g.
  /// every distinct double from `math.sin`) where caching never hits.
  Value primitiveValue(Object? raw) {
    if (raw is Value) return raw;
    final r = interpreter;
    // For scalar primitives (numbers, nil, bools) from builtin results,
    // use a transient Value to avoid the HashMap overhead in
    // constantPrimitiveValue.  Cache hits are extremely unlikely here
    // since values like math.sin(i) are almost always unique.
    // See doc/decisions.md for rationale and benchmark data.
    if (r != null && (raw is num || raw == null || raw is bool)) {
      return Value.transientPrimitive(raw, interpreter: r);
    }
    return cachedPrimitiveOrValue(interpreter, raw);
  }

  /// Reuses runtime-cached wrappers for public Dart string results while
  /// preserving the public `raw is String` interop contract.
  Value dartStringValue(String raw) {
    return cachedPrimitiveOrValue(interpreter, raw);
  }
}

/// Optional interface for builtins that need to keep GC-visible references.
abstract interface class BuiltinFunctionGcRefs {
  Iterable<Object?> getGcReferences();
}
