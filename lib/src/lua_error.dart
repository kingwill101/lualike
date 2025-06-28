import 'package:source_span/source_span.dart';
import 'ast.dart';
import 'lua_stack_trace.dart';

/// Exception thrown for Lua runtime errors with source location information.
///
/// This exception includes source span information to provide better error messages
/// with line and column numbers where the error occurred.
class LuaError implements Exception {
  /// The error message.
  final String message;

  /// The source span where the error occurred.
  final SourceSpan? span;

  /// The AST node where the error occurred.
  final AstNode? node;

  /// The original exception that caused this error.
  final Object? cause;

  /// The Dart stack trace at the time the error occurred.
  final StackTrace? stackTrace;

  /// The Lua call stack at the time the error occurred.
  final LuaStackTrace? luaStackTrace;

  /// Creates a new Lua error with the given message and optional source information.
  LuaError(
    this.message, {
    this.span,
    this.node,
    this.cause,
    this.stackTrace,
    this.luaStackTrace,
  });

  /// Creates a LuaError from an AST node and message.
  factory LuaError.fromNode(
    AstNode node,
    String message, {
    Object? cause,
    StackTrace? stackTrace,
    LuaStackTrace? luaStackTrace,
  }) {
    return LuaError(
      message,
      node: node,
      span: node.span,
      cause: cause,
      stackTrace: stackTrace,
      luaStackTrace: luaStackTrace,
    );
  }

  /// Creates a LuaError from another exception.
  factory LuaError.fromException(
    Object exception, {
    String? message,
    SourceSpan? span,
    AstNode? node,
    StackTrace? stackTrace,
    LuaStackTrace? luaStackTrace,
  }) {
    // If the exception is already a LuaError, just return it
    if (exception is LuaError) {
      return exception;
    }

    return LuaError(
      message ?? 'Error: ${exception.toString()}',
      span: span,
      node: node,
      cause: exception,
      stackTrace: stackTrace,
      luaStackTrace: luaStackTrace,
    );
  }

  /// Creates a type error with the given message.
  ///
  /// This is for errors like "attempt to call a nil value".
  factory LuaError.typeError(
    String message, {
    SourceSpan? span,
    AstNode? node,
    Object? cause,
    StackTrace? stackTrace,
    LuaStackTrace? luaStackTrace,
  }) {
    return LuaError(
      message,
      span: span,
      node: node,
      cause: cause,
      stackTrace: stackTrace,
      luaStackTrace: luaStackTrace,
    );
  }

  /// Returns a formatted error message with source location information if available.
  String formatError() {
    final buffer = StringBuffer(message);

    if (span != null) {
      buffer.writeln();
      buffer.write(span!.message('', color: false));
    } else if (node != null && node?.span != null) {
      buffer.writeln();
      buffer.write(node!.span!.message('', color: false));
    }

    if (luaStackTrace != null) {
      buffer.writeln();
      buffer.write(luaStackTrace!.format());
    }

    if (cause != null && cause != this) {
      buffer.writeln();
      buffer.write('Caused by: $cause');
    }

    return buffer.toString();
  }

  @override
  String toString() => formatError();
}
