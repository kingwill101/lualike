/// Web-safe logger implementation.
///
/// This keeps the public logging API intact while avoiding contextual's
/// transitive runtime dependencies during browser compilation.
library;

import '../ast.dart';
import '../lua_error.dart';
import '../lua_stack_trace.dart';
import 'level.dart';

class Logger {
  static bool enabled = false;
  static Set<String>? _categoryFilters;
  static Level? logLevelFilter;

  static void initialize({bool pretty = true}) {}

  static void setCategoryFilter(String? category) {
    if (category == null || category.isEmpty) {
      _categoryFilters = null;
    } else {
      _categoryFilters = {category};
    }
  }

  static void setCategoryFilters(Set<String>? categories) {
    _categoryFilters = (categories == null || categories.isEmpty)
        ? null
        : categories;
  }

  static void setLevelFilter(Level? level) {
    logLevelFilter = level;
  }

  static void setEnabled(bool isEnabled) {
    enabled = isEnabled;
    if (enabled) {
      debug('Logging enabled');
    }
  }

  static void setDefaultLevel(Object level) {}

  static void setDispatchMode(Object mode) {}
  static void setSink(Object sink) {}
  static void useContextualBackend({bool pretty = true}) {
    initialize(pretty: pretty);
  }

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
      level: Level.debug,
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
      level: Level.info,
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
      level: Level.warning,
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
    if (error is LuaError) {
      _log(
        level: Level.error,
        message: error.formatError(),
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
      level: Level.error,
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

  static void debugLazy(
    String Function() messageBuilder, {
    String? category,
    Set<String>? categories,
    Map<String, Object?> Function()? contextBuilder,
    AstNode? node,
    LuaStackTrace? luaStackTrace,
  }) {
    if (!_shouldLog(Level.debug, category, categories)) return;
    _log(
      level: Level.debug,
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
    if (!_shouldLog(Level.info, category, categories)) return;
    _log(
      level: Level.info,
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
    if (!_shouldLog(Level.warning, category, categories)) return;
    _log(
      level: Level.warning,
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
    if (!_shouldLog(Level.error, category, categories)) return;
    _log(
      level: Level.error,
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

  static bool _shouldLog(
    Level level,
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

  static bool _passesLevel(Level level) {
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
    required Level level,
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

    final parts = <String>[];
    parts.add(_levelName(level));

    final cats = _combineCategories(singleCategory, categories);
    if (cats.isNotEmpty) {
      parts.add('[${cats.join(",")}]');
    }

    parts.add(message);

    if (node != null && node.span != null) {
      final span = node.span!;
      parts.add(
        '@${span.sourceUrl?.path}:${span.start.line}:${span.start.column}',
      );
    }
    if (context != null && context.isNotEmpty) {
      parts.add(context.toString());
    }
    if (error != null) {
      parts.add('error=$error');
    }
    if (stackTrace != null) {
      parts.add(stackTrace.toString());
    }
    if (luaStackTrace != null) {
      parts.add(luaStackTrace.format());
    }

    print(parts.join(' '));
  }

  static String _levelName(Level level) {
    switch (level) {
      case Level.debug:
        return 'DEBUG';
      case Level.notice:
        return 'NOTICE';
      case Level.info:
        return 'INFO';
      case Level.warning:
        return 'WARNING';
      case Level.error:
        return 'ERROR';
      case Level.critical:
        return 'CRITICAL';
      case Level.alert:
        return 'ALERT';
      case Level.emergency:
        return 'EMERGENCY';
    }
  }
}

int _severity(Level level) {
  switch (level) {
    case Level.debug:
      return 10;
    case Level.notice:
      return 20;
    case Level.info:
      return 30;
    case Level.warning:
      return 40;
    case Level.error:
      return 50;
    case Level.critical:
      return 55;
    case Level.alert:
      return 60;
    case Level.emergency:
      return 70;
  }
}
