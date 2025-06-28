/// A simple logger for the LuaLike interpreter.
///
/// This class provides a centralized way to handle debug logging throughout
/// the interpreter. Logging can be globally enabled or disabled, with separate
/// handling for debug and error messages.
library;

import 'ast.dart';
import 'lua_error.dart';
import 'lua_stack_trace.dart';

class Logger {
  /// Whether debug logging is enabled.
  static bool enabled = false;

  /// A public sink for all logger output, allowing redirection for testing.
  static void Function(Object?)? outputSink;

  /// Log a debug message if logging is enabled.
  ///
  /// @param message The message to log.
  /// @param category Optional category for the log message.
  /// @param node Optional AST node for position information.
  static void debug(String message, {String? category, AstNode? node}) {
    if (!enabled) return;
    String positionInfo = '';
    if (node != null && node.span != null) {
      final span = node.span!;
      positionInfo =
          ' [${span.sourceUrl?.path}:${span.start.line}:${span.start.column}-${span.end.line}:${span.end.column}]';
    }

    final logMessage = '[DEBUG]$positionInfo [$category] $message';
    if (outputSink != null) {
      outputSink!(logMessage);
    } else {
      print(logMessage);
    }
  }

  /// Log an error message.
  ///
  /// Error messages are always logged regardless of the enabled state.
  ///
  /// @param message The error message to log.
  /// @param error Optional error object.
  /// @param node Optional AST node for position information.
  static void error(
    String message, {
    Object? error,
    String? category,
    StackTrace? trace,
    AstNode? node,
    LuaStackTrace? luaStackTrace,
  }) {
    final errorDetails = error != null ? ' - $error' : '';
    // If the error is a LuaError, use its formatted message
    if (error is LuaError) {
      final errorMessage = '[ERROR] [$category] ${error.formatError()}';
      if (outputSink != null) {
        outputSink!(errorMessage);
      } else {
        print(errorMessage);
      }
      if (trace != null) {
        if (outputSink != null) {
          outputSink!(trace);
        } else {
          print(trace);
        }
      }
      return;
    }

    String positionInfo = '';
    if (node != null && node.span != null) {
      final span = node.span!;
      positionInfo =
          ' [${span.start.line}:${span.start.column}-${span.end.line}:${span.end.column}]';
    }

    final errorMessage =
        '[ERROR]$positionInfo [$category] $message$errorDetails';
    if (outputSink != null) {
      outputSink!(errorMessage);
    } else {
      print(errorMessage);
    }

    if (luaStackTrace != null) {
      if (outputSink != null) {
        outputSink!(luaStackTrace.format());
      } else {
        print(luaStackTrace.format());
      }
    }

    if (trace != null) {
      if (outputSink != null) {
        outputSink!(trace);
      } else {
        print(trace);
      }
    }
  }

  /// Create and log a LuaError with source information.
  ///
  /// @param message The error message.
  /// @param node The AST node where the error occurred.
  /// @param cause The original exception that caused this error.
  /// @param category Optional category for the log message.
  /// @param trace Optional stack trace.
  static LuaError luaError(
    String message, {
    AstNode? node,
    Object? cause,
    String? category,
    StackTrace? trace,
    LuaStackTrace? luaStackTrace,
  }) {
    final luaError = node != null
        ? LuaError.fromNode(
            node,
            message,
            cause: cause,
            stackTrace: trace,
            luaStackTrace: luaStackTrace,
          )
        : LuaError(
            message,
            cause: cause,
            stackTrace: trace,
            luaStackTrace: luaStackTrace,
          );

    error(
      message,
      error: luaError,
      category: category,
      trace: trace,
      luaStackTrace: luaStackTrace,
    );
    return luaError;
  }

  /// Enable or disable logging.
  ///
  /// @param isEnabled Whether logging should be enabled.
  static void setEnabled(bool isEnabled) {
    enabled = isEnabled;
    if (enabled) {
      debug('Logging enabled');
    }
  }
}
