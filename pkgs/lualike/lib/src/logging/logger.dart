/// A simplified logging facade that uses the contextual package directly.
///
/// This module provides a thin wrapper around the contextual logging library,
/// adding Lualike-specific features like AST node position tracking and Lua
/// stack traces while delegating all the heavy lifting to contextual.
library;

import '../ast.dart';
import '../lua_error.dart';
import '../lua_stack_trace.dart';
import 'package:contextual/contextual.dart' as ctx;

class Logger {
  /// The underlying contextual logger instance
  static ctx.Logger? _logger;

  /// Whether logging is enabled
  static bool enabled = false;

  /// Category filters (any-match). Null/empty means no filter.
  static Set<String>? _categoryFilters;

  /// Level filter. Null means no filter.
  static ctx.Level? logLevelFilter;

  /// Initialize the logging subsystem with a pretty console output by default
  static void initialize({bool pretty = true}) {
    final formatter = pretty
        ? ctx.PrettyLogFormatter()
        : ctx.PlainTextLogFormatter();
    _logger = ctx.Logger();
    _logger!.addChannel(
      'console',
      ctx.ConsoleLogDriver(),
      formatter: formatter,
    );
  }

  /// Ensure logger is initialized (lazy init)
  static void _ensureInitialized() {
    _logger ??= ctx.Logger()
      ..addChannel(
        'console',
        ctx.ConsoleLogDriver(),
        formatter: ctx.PrettyLogFormatter(),
      );
  }

  /// Set category filter (backward compatibility)
  static void setCategoryFilter(String? category) {
    if (category == null || category.isEmpty) {
      _categoryFilters = null;
    } else {
      _categoryFilters = {category};
    }
  }

  /// Set multiple category filters
  static void setCategoryFilters(Set<String>? categories) {
    _categoryFilters = (categories == null || categories.isEmpty)
        ? null
        : categories;
  }

  /// Set the log level filter
  static void setLevelFilter(ctx.Level? level) {
    logLevelFilter = level;
  }

  /// Enable or disable logging
  static void setEnabled(bool isEnabled) {
    enabled = isEnabled;
    if (enabled) {
      _ensureInitialized();
      debug('Logging enabled');
    }
  }

  /// Deprecated no-op: retained for backward compatibility
  static void setDefaultLevel(Object level) {}

  /// No-op compatibility methods
  static void setDispatchMode(Object mode) {}
  static void setSink(Object sink) {}
  static void useContextualBackend({bool pretty = true}) {
    initialize(pretty: pretty);
  }

  // ---------- Public logging APIs ----------

  static void debug(
    String message, {
    String? category,
    Set<String>? categories,
    Map<String, Object?>? context,
    String? source,
    AstNode? node,
    LuaStackTrace? luaStackTrace,
  }) {
    _log(
      level: ctx.Level.debug,
      message: message,
      singleCategory: category,
      categories: categories,
      context: context,
      node: node,
      luaStackTrace: luaStackTrace,
    );
  }

  static void info(
    String message, {
    String? category,
    Set<String>? categories,
    Map<String, Object?>? context,
    String? source,
    AstNode? node,
    LuaStackTrace? luaStackTrace,
  }) {
    _log(
      level: ctx.Level.info,
      message: message,
      singleCategory: category,
      categories: categories,
      context: context,
      node: node,
      luaStackTrace: luaStackTrace,
    );
  }

  static void warning(
    String message, {
    Object? error,
    String? category,
    Set<String>? categories,
    Map<String, Object?>? context,
    StackTrace? trace,
    AstNode? node,
    LuaStackTrace? luaStackTrace,
  }) {
    _log(
      level: ctx.Level.warning,
      message: message,
      singleCategory: category,
      categories: categories,
      context: context,
      node: node,
      error: error,
      stackTrace: trace,
      luaStackTrace: luaStackTrace,
    );
  }

  static void error(
    String message, {
    Object? error,
    String? category,
    Set<String>? categories,
    Map<String, Object?>? context,
    StackTrace? trace,
    AstNode? node,
    LuaStackTrace? luaStackTrace,
  }) {
    // If the error is a LuaError, prefer its formatted message
    if (error is LuaError) {
      final formatted = error.formatError();
      _log(
        level: ctx.Level.error,
        message: formatted,
        singleCategory: category,
        categories: categories,
        context: context,
        node: node,
        error: error,
        stackTrace: trace,
        luaStackTrace: luaStackTrace,
      );
      return;
    }
    _log(
      level: ctx.Level.error,
      message: message,
      singleCategory: category,
      categories: categories,
      context: context,
      node: node,
      error: error,
      stackTrace: trace,
      luaStackTrace: luaStackTrace,
    );
  }

  // ---------- Lazy APIs (zero-cost when disabled/filtered) ----------

  static void debugLazy(
    String Function() messageBuilder, {
    String? category,
    Set<String>? categories,
    Map<String, Object?> Function()? contextBuilder,
    AstNode? node,
    LuaStackTrace? luaStackTrace,
  }) {
    if (!_shouldLog(ctx.Level.debug, category, categories)) return;
    _log(
      level: ctx.Level.debug,
      message: messageBuilder(),
      singleCategory: category,
      categories: categories,
      context: contextBuilder?.call(),
      node: node,
      luaStackTrace: luaStackTrace,
    );
  }

  static void infoLazy(
    String Function() messageBuilder, {
    String? category,
    Set<String>? categories,
    Map<String, Object?> Function()? contextBuilder,
    AstNode? node,
    LuaStackTrace? luaStackTrace,
  }) {
    if (!_shouldLog(ctx.Level.info, category, categories)) return;
    _log(
      level: ctx.Level.info,
      message: messageBuilder(),
      singleCategory: category,
      categories: categories,
      context: contextBuilder?.call(),
      node: node,
      luaStackTrace: luaStackTrace,
    );
  }

  static void warningLazy(
    String Function() messageBuilder, {
    Object? error,
    String? category,
    Set<String>? categories,
    Map<String, Object?> Function()? contextBuilder,
    StackTrace? trace,
    AstNode? node,
    LuaStackTrace? luaStackTrace,
  }) {
    if (!_shouldLog(ctx.Level.warning, category, categories)) return;
    _log(
      level: ctx.Level.warning,
      message: messageBuilder(),
      singleCategory: category,
      categories: categories,
      context: contextBuilder?.call(),
      node: node,
      error: error,
      stackTrace: trace,
      luaStackTrace: luaStackTrace,
    );
  }

  static void errorLazy(
    String Function() messageBuilder, {
    Object? error,
    String? category,
    Set<String>? categories,
    Map<String, Object?> Function()? contextBuilder,
    StackTrace? trace,
    AstNode? node,
    LuaStackTrace? luaStackTrace,
  }) {
    if (!_shouldLog(ctx.Level.error, category, categories)) return;
    _log(
      level: ctx.Level.error,
      message: messageBuilder(),
      singleCategory: category,
      categories: categories,
      context: contextBuilder?.call(),
      node: node,
      error: error,
      stackTrace: trace,
      luaStackTrace: luaStackTrace,
    );
  }

  // ---------- Internal helpers ----------

  static bool _shouldLog(
    ctx.Level level,
    String? singleCategory,
    Set<String>? categories,
  ) {
    if (!enabled) return false;
    if (!_passesLevel(level)) return false;

    final cats = _combineCategories(singleCategory, categories);
    if (_categoryFilters != null && _categoryFilters!.isNotEmpty) {
      if (cats.isEmpty) return false;
      if (!cats.any((c) => _categoryFilters!.contains(c))) return false;
    }
    return true;
  }

  static bool _passesLevel(ctx.Level level) {
    if (logLevelFilter == null) return true;
    return _severity(level) >= _severity(logLevelFilter!);
  }

  static Set<String> _combineCategories(
    String? singleCategory,
    Set<String>? categories,
  ) {
    final set = <String>{};
    if (singleCategory != null && singleCategory.isNotEmpty) {
      set.add(singleCategory);
    }
    if (categories != null && categories.isNotEmpty) {
      set.addAll(categories);
    }
    return set;
  }

  static void _log({
    required ctx.Level level,
    required String message,
    String? singleCategory,
    Set<String>? categories,
    Map<String, Object?>? context,
    AstNode? node,
    Object? error,
    StackTrace? stackTrace,
    LuaStackTrace? luaStackTrace,
  }) {
    if (!_shouldLog(level, singleCategory, categories)) return;

    _ensureInitialized();

    final cats = _combineCategories(singleCategory, categories);
    final enrichedContext = <String, Object?>{};

    // Add user context
    if (context != null) enrichedContext.addAll(context);

    // Add categories
    if (cats.isNotEmpty) enrichedContext['categories'] = cats.toList();

    // Add AST node position info
    if (node != null && node.span != null) {
      final span = node.span!;
      enrichedContext['source'] = span.sourceUrl?.path;
      enrichedContext['position'] =
          '${span.start.line}:${span.start.column}-${span.end.line}:${span.end.column}';
    }

    // Add error info
    if (error != null) enrichedContext['error'] = error.toString();
    if (stackTrace != null) {
      enrichedContext['stackTrace'] = stackTrace.toString();
    }

    // Add Lua stack trace
    if (luaStackTrace != null) {
      enrichedContext['luaStackTrace'] = luaStackTrace.format();
    }

    // Let contextual handle everything
    _logger!.log(level, message, ctx.Context(enrichedContext));
  }
}

int _severity(ctx.Level level) {
  switch (level) {
    case ctx.Level.debug:
      return 10;
    case ctx.Level.notice:
      return 20;
    case ctx.Level.info:
      return 30;
    case ctx.Level.warning:
      return 40;
    case ctx.Level.error:
      return 50;
    case ctx.Level.critical:
      return 55;
    case ctx.Level.alert:
      return 60;
    case ctx.Level.emergency:
      return 70;
  }
}
