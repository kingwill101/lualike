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
  LuaStackTrace? luaStackTrace;

  /// Whether protected-call packaging should leave the message unadorned.
  ///
  /// This is used for cases like `error(message, 0)`, where Lua suppresses the
  /// automatic `file:line:` prefix even when the error object flows through
  /// `pcall`/`xpcall`.
  final bool suppressAutomaticLocation;

  /// Whether protected-call packaging should preserve this message verbatim.
  ///
  /// Builtin functions behave like Lua C functions: under `pcall`/`xpcall`
  /// their errors are typically returned as raw messages, while unprotected
  /// execution still reports the caller location when the error escapes the
  /// chunk. This flag lets the protected-call layer preserve that behavior
  /// without suppressing normal top-level reporting.
  final bool suppressProtectedCallLocation;

  /// Optional 1-based source line override for protected-call packaging.
  ///
  /// Some runtime errors originate from operators or call sites inside larger
  /// multiline spans. Lua reports the operator/call line for those failures,
  /// which can be more precise than the active statement line or the node span.
  final int? lineNumber;

  /// Tracks whether this error has already been reported to avoid duplicate output.
  bool hasBeenReported;

  /// Creates a new Lua error with the given message and optional source information.
  LuaError(
    this.message, {
    this.span,
    this.node,
    this.cause,
    this.stackTrace,
    this.luaStackTrace,
    this.suppressAutomaticLocation = false,
    this.suppressProtectedCallLocation = false,
    this.lineNumber,
    this.hasBeenReported = false,
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
      suppressAutomaticLocation: false,
      suppressProtectedCallLocation: false,
      lineNumber: null,
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
      suppressAutomaticLocation: false,
      suppressProtectedCallLocation: false,
      lineNumber: null,
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
    int? lineNumber,
  }) {
    return LuaError(
      message,
      span: span,
      node: node,
      cause: cause,
      stackTrace: stackTrace,
      luaStackTrace: luaStackTrace,
      suppressAutomaticLocation: false,
      suppressProtectedCallLocation: false,
      lineNumber: lineNumber,
    );
  }

  /// Returns a copy that preserves the current message under protected calls.
  LuaError withProtectedCallLocationSuppressed() {
    if (suppressProtectedCallLocation) {
      return this;
    }
    return LuaError(
      message,
      span: span,
      node: node,
      cause: cause,
      stackTrace: stackTrace,
      luaStackTrace: luaStackTrace,
      suppressAutomaticLocation: suppressAutomaticLocation,
      suppressProtectedCallLocation: true,
      lineNumber: lineNumber,
      hasBeenReported: hasBeenReported,
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

    if (cause != null && cause != this && cause.toString() != message) {
      buffer.writeln();
      buffer.write('Caused by: $cause');
    }

    return buffer.toString();
  }

  @override
  String toString() => formatError();
}
