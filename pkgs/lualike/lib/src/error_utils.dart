import 'package:source_span/source_span.dart';

import 'ast.dart';
import 'lua_error.dart';
import 'lua_stack_trace.dart';

/// Throws a Lua runtime error with the given message.
Never throwLuaError(
  String message, {
  SourceSpan? span,
  AstNode? node,
  Object? cause,
  StackTrace? stackTrace,
  LuaStackTrace? luaStackTrace,
}) {
  throw LuaError(
    message,
    span: span,
    node: node,
    cause: cause,
    stackTrace: stackTrace ?? StackTrace.current,
    luaStackTrace: luaStackTrace,
  );
}

/// Throws a Lua runtime error from an AST node.
Never throwLuaErrorFromNode(
  AstNode node,
  String message, {
  Object? cause,
  StackTrace? stackTrace,
  LuaStackTrace? luaStackTrace,
}) {
  throw LuaError.fromNode(
    node,
    message,
    cause: cause,
    stackTrace: stackTrace ?? StackTrace.current,
    luaStackTrace: luaStackTrace,
  );
}

/// Throws a Lua type error.
Never throwLuaTypeError(
  String message, {
  SourceSpan? span,
  AstNode? node,
  Object? cause,
  StackTrace? stackTrace,
  LuaStackTrace? luaStackTrace,
}) {
  throw LuaError.typeError(
    message,
    span: span,
    node: node,
    cause: cause,
    stackTrace: stackTrace ?? StackTrace.current,
    luaStackTrace: luaStackTrace,
  );
}

/// Converts any exception to a LuaError.
///
/// If the exception is already a LuaError, it is returned as is.
/// Otherwise, a new LuaError is created with the exception as the cause.
LuaError toLuaError(
  Object exception, {
  String? message,
  SourceSpan? span,
  AstNode? node,
  StackTrace? stackTrace,
  LuaStackTrace? luaStackTrace,
}) {
  if (exception is LuaError) {
    return exception;
  }

  return LuaError.fromException(
    exception,
    message: message,
    span: span,
    node: node,
    stackTrace: stackTrace ?? StackTrace.current,
    luaStackTrace: luaStackTrace,
  );
}

/// Runs a function and catches any exceptions, converting them to LuaError.
///
/// This is useful for wrapping code that might throw exceptions that aren't
/// LuaError instances.
T runWithLuaErrorHandling<T>(
  T Function() fn, {
  String? message,
  SourceSpan? span,
  AstNode? node,
  LuaStackTrace? luaStackTrace,
}) {
  try {
    return fn();
  } catch (e, st) {
    throw toLuaError(
      e,
      message: message,
      span: span,
      node: node,
      stackTrace: st,
      luaStackTrace: luaStackTrace,
    );
  }
}
