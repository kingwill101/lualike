import 'package:logging/logging.dart' as pkg_logging;
import 'package:lualike/src/builtin_function.dart';
import 'package:lualike/src/logging/logger.dart';
import 'package:lualike/src/lua_error.dart';
import 'package:lualike/src/lua_string.dart';
import 'package:lualike/src/value.dart';

import 'library.dart';

class LoggingLibrary extends Library {
  @override
  String get name => "logging";

  @override
  void registerFunctions(LibraryRegistrationContext context) {
    context.define("enable", _LoggingEnable());
    context.define("disable", _LoggingDisable());
    context.define("is_enabled", _LoggingIsEnabled());
    context.define("set_level", _LoggingSetLevel());
    context.define("get_level", _LoggingGetLevel());
    context.define("set_category", _LoggingSetCategory());
    context.define("get_category", _LoggingGetCategory());
    context.define("reset_filters", _LoggingResetFilters());
  }
}

class _LoggingEnable extends BuiltinFunction {
  _LoggingEnable() : super();

  @override
  Object? call(List<Object?> args) {
    final level = _extractLevel(
      args.isNotEmpty ? args[0] : null,
      fallback: pkg_logging.Level.FINE,
    );
    final category = args.length >= 2
        ? _extractString(args[1], allowNull: true)
        : null;

    Logger.initialize(defaultLevel: level);
    Logger.setCategoryFilter(category);
    Logger.setDefaultLevel(level);
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
    Logger.initialize(defaultLevel: level);
    Logger.setDefaultLevel(level);
    Logger.setLevelFilter(level);
    return Value(true);
  }
}

class _LoggingGetLevel extends BuiltinFunction {
  _LoggingGetLevel() : super();

  @override
  Object? call(List<Object?> args) {
    final level = Logger.logLevelFilter ?? pkg_logging.Logger.root.level;
    return Value(level.name);
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

class _LoggingGetCategory extends BuiltinFunction {
  _LoggingGetCategory() : super();

  @override
  Object? call(List<Object?> args) {
    final category = Logger.logCategoryFilter;
    if (category == null) {
      return Value(null);
    }
    return Value(category);
  }
}

class _LoggingResetFilters extends BuiltinFunction {
  _LoggingResetFilters() : super();

  @override
  Object? call(List<Object?> args) {
    Logger.setCategoryFilter(null);
    Logger.setLevelFilter(null);
    Logger.setDefaultLevel(pkg_logging.Level.INFO);
    return Value(true);
  }
}

pkg_logging.Level _extractLevel(
  Object? arg, {
  pkg_logging.Level fallback = pkg_logging.Level.INFO,
}) {
  final name = _extractString(arg, allowNull: true);
  if (name == null || name.isEmpty) {
    return fallback;
  }

  final level = pkg_logging.Level.LEVELS.firstWhere(
    (lvl) => lvl.name.toUpperCase() == name.toUpperCase(),
    orElse: () => throw LuaError("unknown logging level '$name'"),
  );
  return level;
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
