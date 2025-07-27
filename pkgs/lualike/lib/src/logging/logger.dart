/// A simple logger for the LuaLike interpreter.
///
/// This class provides a centralized way to handle debug logging throughout
/// the interpreter. Logging can be globally enabled or disabled, with separate
/// handling for debug and error messages.
library;

import '../ast.dart';
import '../lua_error.dart';
import '../lua_stack_trace.dart';
import 'package:logging/logging.dart' as pkg_logging;

class Logger {
  /// Whether debug logging is enabled.
  static bool enabled = false;

  static final Map<String, pkg_logging.Logger> _categoryLoggers = {};

  /// Optional filters for log output
  static String? logCategoryFilter;
  static pkg_logging.Level? logLevelFilter;

  /// Set the log category filter (for CLI --category)
  static void setCategoryFilter(String? category) {
    logCategoryFilter = category;
  }

  /// Set the log level filter (for CLI --level)
  static void setLevelFilter(pkg_logging.Level? level) {
    logLevelFilter = level;
  }

  /// Initialize the root logger and set up a default handler.
  /// Only logs matching the selected category and level are printed.
  static void initialize({
    pkg_logging.Level defaultLevel = pkg_logging.Level.INFO,
  }) {
    pkg_logging.Logger.root.level = defaultLevel;
    pkg_logging.Logger.root.onRecord.listen((record) {
      // Filter by category if set
      if (logCategoryFilter != null && record.loggerName != logCategoryFilter) {
        return;
      }
      // Filter by level if set
      if (logLevelFilter != null && record.level < logLevelFilter!) {
        return;
      }
      final time = record.time.toIso8601String();
      final level = record.level.name;
      final category = record.loggerName;
      final msg = record.message;
      final error = record.error != null ? '\n  Error: ${record.error}' : '';
      final stack = record.stackTrace != null
          ? '\n  StackTrace: ${record.stackTrace}'
          : '';
      print('[$time] [$level] [$category] $msg$error$stack');
    });
  }

  /// Get or create a logger for a given category.
  static pkg_logging.Logger _getLogger(String? category) {
    final name = category ?? 'General';
    return _categoryLoggers.putIfAbsent(name, () => pkg_logging.Logger(name));
  }

  /// Set the log level for a specific category.
  static void setCategoryLevel(String category, pkg_logging.Level level) {
    _getLogger(category).level = level;
  }

  /// Set the default log level for all loggers.
  static void setDefaultLevel(pkg_logging.Level level) {
    pkg_logging.Logger.root.level = level;
  }

  /// Log a debug message if logging is enabled.
  ///
  /// @param message The message to log.
  /// @param category Optional category for the log message.
  /// @param node Optional AST node for position information.
  static void debug(
    String message, {
    String? category,
    String? source,
    AstNode? node,
    LuaStackTrace? luaStackTrace,
  }) {
    if (!enabled) return;
    String positionInfo = '';
    if (node != null && node.span != null) {
      final span = node.span!;
      positionInfo =
          ' [${span.sourceUrl?.path}:${span.start.line}:${span.start.column}-${span.end.line}:${span.end.column}]';
    }
    final logMessage = '$positionInfo$message';
    _getLogger(category).fine(logMessage);
  }

  /// Log an error message.
  ///
  /// Error messages are only logged if logging is enabled.
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
    if (!enabled) return;
    final errorDetails = error != null ? ' - $error' : '';
    if (error is LuaError) {
      final errorMessage = error.formatError();
      _getLogger(category).severe(errorMessage, error, trace);
      if (luaStackTrace != null) {
        _getLogger(category).severe(luaStackTrace.format());
      }
      return;
    }
    String positionInfo = '';
    if (node != null && node.span != null) {
      final span = node.span!;
      positionInfo =
          ' [${span.start.line}:${span.start.column}-${span.end.line}:${span.end.column}]';
    }
    final errorMessage = '$positionInfo$message$errorDetails';
    _getLogger(category).severe(errorMessage, error, trace);
    if (luaStackTrace != null) {
      _getLogger(category).severe(luaStackTrace.format());
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

  static void info(
    String message, {
    String? category,
    String? source,
    AstNode? node,
    LuaStackTrace? luaStackTrace,
  }) {
    if (!enabled) return;
    String positionInfo = '';
    if (node != null && node.span != null) {
      final span = node.span!;
      positionInfo =
          ' [${span.sourceUrl?.path}:${span.start.line}:${span.start.column}-${span.end.line}:${span.end.column}]';
    }
    final logMessage = '$positionInfo$message';
    _getLogger(category).info(logMessage);
  }

  static void warning(
    String message, {
    Object? error,
    String? category,
    StackTrace? trace,
    AstNode? node,
    LuaStackTrace? luaStackTrace,
  }) {
    if (!enabled) return;
    String positionInfo = '';
    if (node != null && node.span != null) {
      final span = node.span!;
      positionInfo =
          ' [${span.sourceUrl?.path}:${span.start.line}:${span.start.column}-${span.end.line}:${span.end.column}]';
    }
    final warningMessage = '$positionInfo$message';
    _getLogger(category).warning(warningMessage, error, trace);
    if (luaStackTrace != null) {
      _getLogger(category).warning(luaStackTrace.format());
    }
  }
}
