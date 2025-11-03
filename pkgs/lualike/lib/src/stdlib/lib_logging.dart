import 'package:contextual/contextual.dart' as ctx;
import 'package:lualike/src/builtin_function.dart';
import 'package:lualike/src/logging/logger.dart';
import 'package:lualike/src/lua_error.dart';
import 'package:lualike/src/lua_string.dart';
import 'package:lualike/src/value.dart';

import 'library.dart';

/// Enhanced Lua logging library that exposes the full power of contextual logging
///
/// Features:
/// - Multiple log levels: debug, info, warning, error
/// - Multiple categories per log message
/// - Structured context data (key-value pairs)
/// - Category filtering (any-match)
/// - Level filtering
///
/// Example usage:
///   logging.enable("DEBUG")
///   logging.debug("Starting process", {category = "App", user = "alice"})
///   logging.info("Request processed", {categories = {"HTTP", "API"}, status = 200})
///   logging.set_categories({"HTTP", "Database"})  -- Only show HTTP and Database logs
class LoggingLibrary extends Library {
  @override
  String get name => "logging";

  @override
  void registerFunctions(LibraryRegistrationContext context) {
    // Configuration functions
    context.define("enable", _LoggingEnable());
    context.define("disable", _LoggingDisable());
    context.define("is_enabled", _LoggingIsEnabled());
    context.define("set_level", _LoggingSetLevel());
    context.define("get_level", _LoggingGetLevel());
    context.define("set_category", _LoggingSetCategory());
    context.define("set_categories", _LoggingSetCategories());
    context.define("reset_filters", _LoggingResetFilters());

    // Logging functions with full context support
    context.define("debug", _LoggingDebug());
    context.define("info", _LoggingInfo());
    context.define("warning", _LoggingWarning());
    context.define("error", _LoggingError());
  }
}

class _LoggingEnable extends BuiltinFunction {
  _LoggingEnable() : super();

  @override
  Object? call(List<Object?> args) {
    final level = _extractLevel(
      args.isNotEmpty ? args[0] : null,
      fallback: ctx.Level.debug,
    );
    final category = args.length >= 2
        ? _extractString(args[1], allowNull: true)
        : null;

    Logger.initialize();
    Logger.setCategoryFilter(category);
    Logger.setLevelFilter(level);
    Logger.setEnabled(true);

    return Value(true);
  }
}

class _LoggingDisable extends BuiltinFunction {
  _LoggingDisable() : super();

  @override
  Object? call(List<Object?> args) {
    Logger.setEnabled(false);
    return Value(true);
  }
}

class _LoggingIsEnabled extends BuiltinFunction {
  _LoggingIsEnabled() : super();

  @override
  Object? call(List<Object?> args) {
    return Value(Logger.enabled);
  }
}

class _LoggingSetLevel extends BuiltinFunction {
  _LoggingSetLevel() : super();

  @override
  Object? call(List<Object?> args) {
    if (args.isEmpty) {
      throw LuaError("logging.set_level expects a level name");
    }
    final level = _extractLevel(args[0]);
    Logger.initialize();
    Logger.setLevelFilter(level);
    return Value(true);
  }
}

class _LoggingGetLevel extends BuiltinFunction {
  _LoggingGetLevel() : super();

  @override
  Object? call(List<Object?> args) {
    final level = Logger.logLevelFilter;
    if (level == null) {
      return Value(null);
    }
    return Value(_levelToString(level));
  }
}

class _LoggingSetCategory extends BuiltinFunction {
  _LoggingSetCategory() : super();

  @override
  Object? call(List<Object?> args) {
    if (args.isEmpty) {
      throw LuaError("logging.set_category expects a category name or nil");
    }
    final category = _extractString(args[0], allowNull: true);
    Logger.setCategoryFilter(category);
    return Value(true);
  }
}

class _LoggingSetCategories extends BuiltinFunction {
  _LoggingSetCategories() : super();

  @override
  Object? call(List<Object?> args) {
    if (args.isEmpty) {
      Logger.setCategoryFilters(null);
      return Value(true);
    }

    final categoriesArg = args[0];
    if (categoriesArg == null ||
        (categoriesArg is Value && categoriesArg.raw == null)) {
      Logger.setCategoryFilters(null);
      return Value(true);
    }

    final categories = _extractCategories(categoriesArg);
    Logger.setCategoryFilters(categories);
    return Value(true);
  }
}

class _LoggingResetFilters extends BuiltinFunction {
  _LoggingResetFilters() : super();

  @override
  Object? call(List<Object?> args) {
    Logger.setCategoryFilter(null);
    Logger.setLevelFilter(null);
    return Value(true);
  }
}

// ========== Logging Functions ==========

class _LoggingDebug extends BuiltinFunction {
  _LoggingDebug() : super();

  @override
  Object? call(List<Object?> args) {
    if (args.isEmpty) {
      throw LuaError("logging.debug expects a message");
    }

    final message = _extractString(args[0], allowNull: false) ?? '';
    final opts = args.length > 1 ? args[1] : null;
    final logContext = _extractLogContext(opts);

    Logger.debug(
      message,
      category: logContext.singleCategory,
      categories: logContext.categories,
      context: logContext.context,
    );

    return Value(true);
  }
}

class _LoggingInfo extends BuiltinFunction {
  _LoggingInfo() : super();

  @override
  Object? call(List<Object?> args) {
    if (args.isEmpty) {
      throw LuaError("logging.info expects a message");
    }

    final message = _extractString(args[0], allowNull: false) ?? '';
    final opts = args.length > 1 ? args[1] : null;
    final logContext = _extractLogContext(opts);

    Logger.info(
      message,
      category: logContext.singleCategory,
      categories: logContext.categories,
      context: logContext.context,
    );

    return Value(true);
  }
}

class _LoggingWarning extends BuiltinFunction {
  _LoggingWarning() : super();

  @override
  Object? call(List<Object?> args) {
    if (args.isEmpty) {
      throw LuaError("logging.warning expects a message");
    }

    final message = _extractString(args[0], allowNull: false) ?? '';
    final opts = args.length > 1 ? args[1] : null;
    final logContext = _extractLogContext(opts);

    Logger.warning(
      message,
      category: logContext.singleCategory,
      categories: logContext.categories,
      context: logContext.context,
    );

    return Value(true);
  }
}

class _LoggingError extends BuiltinFunction {
  _LoggingError() : super();

  @override
  Object? call(List<Object?> args) {
    if (args.isEmpty) {
      throw LuaError("logging.error expects a message");
    }

    final message = _extractString(args[0], allowNull: false) ?? '';
    final opts = args.length > 1 ? args[1] : null;
    final logContext = _extractLogContext(opts);

    Logger.error(
      message,
      category: logContext.singleCategory,
      categories: logContext.categories,
      context: logContext.context,
    );

    return Value(true);
  }
}

ctx.Level _extractLevel(Object? arg, {ctx.Level fallback = ctx.Level.info}) {
  final name = _extractString(arg, allowNull: true);
  if (name == null || name.isEmpty) {
    return fallback;
  }

  final upperName = name.toUpperCase();
  switch (upperName) {
    case 'DEBUG':
    case 'FINE':
    case 'FINER':
    case 'FINEST':
      return ctx.Level.debug;
    case 'NOTICE':
      return ctx.Level.notice;
    case 'INFO':
    case 'CONFIG':
      return ctx.Level.info;
    case 'WARNING':
    case 'SEVERE':
      return ctx.Level.warning;
    case 'ERROR':
      return ctx.Level.error;
    case 'CRITICAL':
      return ctx.Level.critical;
    case 'ALERT':
      return ctx.Level.alert;
    case 'EMERGENCY':
    case 'SHOUT':
      return ctx.Level.emergency;
    default:
      throw LuaError("unknown logging level '$name'");
  }
}

String _levelToString(ctx.Level level) {
  switch (level) {
    case ctx.Level.debug:
      return 'DEBUG';
    case ctx.Level.notice:
      return 'NOTICE';
    case ctx.Level.info:
      return 'INFO';
    case ctx.Level.warning:
      return 'WARNING';
    case ctx.Level.error:
      return 'ERROR';
    case ctx.Level.critical:
      return 'CRITICAL';
    case ctx.Level.alert:
      return 'ALERT';
    case ctx.Level.emergency:
      return 'EMERGENCY';
  }
}

String? _extractString(Object? arg, {bool allowNull = false}) {
  if (arg == null) {
    return allowNull ? null : '';
  }
  if (arg is Value) {
    if (arg.raw == null) {
      return allowNull ? null : '';
    }
    return _stringFromRaw(arg.raw);
  }
  return _stringFromRaw(arg);
}

String _stringFromRaw(Object? raw) {
  if (raw == null) {
    return '';
  }
  if (raw is LuaString) {
    return raw.toString();
  }
  if (raw is String) {
    return raw;
  }
  return raw.toString();
}

/// Extract a set of categories from a Lua value (table/array)
Set<String> _extractCategories(Object? arg) {
  final categories = <String>{};

  if (arg == null) return categories;

  final raw = arg is Value ? arg.raw : arg;

  if (raw is Map) {
    // Iterate through table (array-like or key-value)
    for (final entry in raw.entries) {
      final value = entry.value;
      if (value != null) {
        categories.add(_stringFromRaw(value));
      }
    }
  } else if (raw is List) {
    // Handle list
    for (final item in raw) {
      if (item != null) {
        categories.add(_stringFromRaw(item));
      }
    }
  } else {
    // Single string
    final str = _stringFromRaw(raw);
    if (str.isNotEmpty) {
      categories.add(str);
    }
  }

  return categories;
}

/// Holds extracted log context from Lua options table
class _LogContext {
  final String? singleCategory;
  final Set<String>? categories;
  final Map<String, Object?>? context;

  _LogContext({this.singleCategory, this.categories, this.context});
}

/// Extract log context from Lua options table
///
/// Expects a table with:
/// - category: string (single category)
/// - categories: table/array (multiple categories)
/// - Any other key-value pairs become context data
_LogContext _extractLogContext(Object? opts) {
  if (opts == null) {
    return _LogContext();
  }

  final raw = opts is Value ? opts.raw : opts;

  if (raw is! Map) {
    // Not a table, no context
    return _LogContext();
  }

  String? singleCategory;
  Set<String>? categories;
  final context = <String, Object?>{};

  for (final entry in raw.entries) {
    final key = _stringFromRaw(entry.key);
    final value = entry.value;
    final rawValue = value is Value ? value.raw : value;

    if (key == 'category') {
      // Single category
      singleCategory = _extractString(value, allowNull: true);
    } else if (key == 'categories') {
      // Multiple categories
      categories = _extractCategories(value);
    } else {
      // Everything else goes into context
      context[key] = _luaValueToDartValue(rawValue);
    }
  }

  return _LogContext(
    singleCategory: singleCategory,
    categories: categories,
    context: context.isEmpty ? null : context,
  );
}

/// Convert Lua value to Dart value for context
Object? _luaValueToDartValue(Object? raw) {
  if (raw == null) return null;

  if (raw is String || raw is num || raw is bool) {
    return raw;
  }

  if (raw is LuaString) {
    return raw.toString();
  }

  if (raw is Map) {
    // Convert table to map
    final map = <String, Object?>{};
    for (final entry in raw.entries) {
      final key = _stringFromRaw(entry.key);
      final value = entry.value;
      map[key] = _luaValueToDartValue(value is Value ? value.raw : value);
    }
    return map;
  }

  if (raw is List) {
    return raw
        .map((item) => _luaValueToDartValue(item is Value ? item.raw : item))
        .toList();
  }

  return raw.toString();
}
