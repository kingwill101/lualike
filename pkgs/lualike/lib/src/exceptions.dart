/// This file contains special-purpose exceptions used for control flow in the Lua interpreter.
///
/// For error handling and reporting Lua runtime errors, use the [LuaError] class instead.
/// These exceptions are not meant to be caught by user code, but are used internally
/// for implementing Lua's control flow mechanisms like coroutines, goto, and break.
library;

import 'dart:async';

import 'package:lualike/src/coroutine.dart' show Coroutine;
import 'package:lualike/src/value.dart';

/// Base class for exceptions used by the interpreter for control flow.
class ControlFlowException implements Exception {}

/// Exception thrown for 'return' statements.
class ReturnException extends ControlFlowException {
  final Object? value; // Can be single value or Value.multi
  ReturnException(this.value);

  @override
  String toString() => "ReturnException: $value";
}

/// Exception used to implement proper tail calls.
///
/// When a function executes `return f(args)` in tail position, the interpreter
/// throws this exception carrying the callee and its arguments. The call site
/// then performs the invocation without growing the call stack (reusing the
/// current frame), satisfying Lua's tail-call semantics.
class TailCallException extends ControlFlowException {
  final dynamic functionValue; // Value | Function* variants | BuiltinFunction
  final List<Object?> args; // Already normalized argument list

  TailCallException(this.functionValue, this.args);

  @override
  String toString() =>
      "TailCallException(${functionValue.runtimeType}, ${args.length} args)";
}

/// Exception thrown for 'break' statements.
class BreakException extends ControlFlowException {}

/// Exception thrown for 'continue' statements (if implemented).
class ContinueException extends ControlFlowException {}

/// Exception thrown for 'goto' statements.
///
/// Carries the target label name to support control flow via goto statements.
class GotoException extends ControlFlowException {
  /// The name of the label to jump to.
  final String label;

  /// Creates a new goto exception targeting the specified label.
  GotoException(this.label);

  @override
  String toString() => label;
}

/// Exception thrown for 'coroutine.yield' calls.
class YieldException extends ControlFlowException {
  // Use non-generic List<Value>
  final List<Value> values;
  // Future that completes with resume args
  final Future<List<Object?>> resumeFuture;
  // The coroutine that yielded
  final Coroutine? coroutine;

  YieldException(this.values, this.resumeFuture, [this.coroutine]);

  @override
  String toString() => "YieldException: $values";
}

class GoToException implements Exception {
  final String label;
  GoToException(this.label);

  @override
  String toString() => "GoToException: $label";
}
